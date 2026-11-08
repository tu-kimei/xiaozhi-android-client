import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:collection';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'pcm_stream_player.dart';
import 'pcm_channel_picker.dart';
import 'voice_activity_detector.dart';

/// 一帧上行音频：Opus 数据 + 该帧 PCM 能量（dB），供本地 VAD 使用
class VoiceFrame {
  final Uint8List opus;
  final double db;
  final double voicing;
  const VoiceFrame(this.opus, this.db, this.voicing);
}

/// 音频工具类，用于处理Opus音频编解码和录制播放
class AudioUtil {
  static const String TAG = "AudioUtil";
  static const int SAMPLE_RATE = 16000;
  static const int CHANNELS = 1;
  static const int FRAME_DURATION = 60; // 毫秒

  static final AudioRecorder _audioRecorder = AudioRecorder();
  static ja.AudioPlayer? _player;
  static bool _isRecorderInitialized = false;
  static bool _isPlayerInitialized = false;
  static bool _isRecording = false;
  static bool _isPlaying = false;
  static final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();
  static String? _tempFilePath;
  static DateTime? _lastFrameAt;

  /// 最近一次收到麦克风数据的时间（用于检测麦克风被其他应用占用）
  static DateTime? get lastFrameAt => _lastFrameAt;
  static Timer? _audioProcessingTimer;

  // Opus相关
  static final _encoder = SimpleOpusEncoder(
    sampleRate: SAMPLE_RATE,
    channels: CHANNELS,
    application: Application.voip,
  );
  // 服务器下行TTS采样率由hello消息的audio_params决定（官方服务器为24000）
  static int _outputSampleRate = 24000;
  static SimpleOpusDecoder _decoder = SimpleOpusDecoder(
    sampleRate: _outputSampleRate,
    channels: CHANNELS,
  );

  // 上行PCM缓冲：录音流的分片长度不固定，需拼成完整的60ms帧再编码
  static final BytesBuilder _pcmBuffer = BytesBuilder(copy: false);
  // 部分机器人（Visbot）麦克风阵列无视单声道配置，返回多声道交错数据
  static PcmChannelPicker? _channelPicker;
  static bool _loggedStride = false;
  static const int _frameBytes = SAMPLE_RATE * FRAME_DURATION ~/ 1000 * 2;

  // 播放串行化，保证Opus包按到达顺序解码和写入
  static Future<void> _playChain = Future.value();

  // 估算已写入播放器的音频何时播放完毕（服务器可能快于实时推送）
  static DateTime _playbackEndsAt = DateTime.now();

  // 抖动缓冲：播放器断粮（网络抖动、UI 卡顿）后先攒够一小段再写入，
  // 避免一帧一帧地断续播放（听起来“卡/闷”）
  // 服务器只按实时速度推送 TTS，几乎没有提前量：开头多攒一些抵御网络抖动；
  // 句中断粮时只补一点点，避免每次都插入长停顿
  static const Duration _startPrebuffer = Duration(milliseconds: 600);
  // 句中断粮后重新攒的量
  static const Duration _rebuffer = Duration(milliseconds: 400);
  static Duration _prebuffer = _startPrebuffer;
  static final BytesBuilder _jitter = BytesBuilder(copy: false);
  static bool _buffering = true;
  static Timer? _jitterFlushTimer;

  static Duration _pcmDuration(int bytes) =>
      Duration(microseconds: bytes ~/ 2 * 1000000 ~/ _outputSampleRate);

  /// 新一段 TTS 开始：开头先攒 [_startPrebuffer] 再播放
  static void beginReply() {
    // 新的一段回答：从干净的队列开始（上一段若有卡住的 future 不再阻塞）
    _playChain = Future.value().then((_) async {
      if (_jitter.length == 0) {
        _buffering = true;
        _prebuffer = _startPrebuffer;
      }
      // 播放器可能在离开/重进通话时被释放：开口前确保可用
      if (!_isPlayerInitialized || _pcmPlayer == null) {
        await initPlayer();
      }
    }).timeout(const Duration(seconds: 3), onTimeout: () {
      print('$TAG: 播放队列卡住，重置');
    });
  }

  /// 等待已收到的音频全部解码写入并播放完毕（含排队中的包）
  static Future<void> whenPlaybackDrained() async {
    Future<void> chain;
    do {
      chain = _playChain;
      await chain;
    } while (!identical(chain, _playChain));
    if (_jitter.length > 0) await _flushJitter();
    final left = remainingPlayback;
    if (left > Duration.zero) await Future.delayed(left);
  }

  /// 剩余未播放完的音频时长（含尚在抖动缓冲中的部分）
  static Duration get remainingPlayback {
    final left = _playbackEndsAt.difference(DateTime.now());
    final queued = _pcmDuration(_jitter.length);
    return (left.isNegative ? Duration.zero : left) + queued;
  }

  /// 根据服务器hello中的audio_params设置下行采样率
  static Future<void> setOutputSampleRate(int sampleRate) async {
    if (sampleRate <= 0 || sampleRate == _outputSampleRate) return;
    print('$TAG: 下行采样率 $_outputSampleRate -> $sampleRate');
    _outputSampleRate = sampleRate;
    _decoder.destroy();
    _decoder = SimpleOpusDecoder(sampleRate: sampleRate, channels: CHANNELS);
    if (_isPlayerInitialized) {
      await initPlayer();
    }
  }

  // 原生 PCM 播放器（见 PcmStreamPlayer.kt）
  static PcmStreamPlayer? _pcmPlayer;

  /// 获取音频流
  static Stream<Uint8List> get audioStream => _audioStreamController.stream;

  static final StreamController<VoiceFrame> _frameController =
      StreamController<VoiceFrame>.broadcast();

  /// 带能量信息的音频帧流（语音通话的本地 VAD 使用）
  static Stream<VoiceFrame> get frameStream => _frameController.stream;

  /// 初始化音频录制器
  static Future<void> initRecorder() async {
    if (_isRecorderInitialized) return;

    print('$TAG: 开始初始化录音器');

    // 更积极地请求所有可能需要的权限
    if (Platform.isAndroid) {
      print('$TAG: 请求Android所需的所有权限');
      Map<Permission, PermissionStatus> statuses =
          await [
            Permission.microphone,
            Permission.storage,
            Permission.manageExternalStorage,
            Permission.bluetooth,
            Permission.bluetoothConnect,
            Permission.bluetoothScan,
          ].request();

      print('$TAG: 权限状态:');
      statuses.forEach((permission, status) {
        print('$TAG: $permission: $status');
      });

      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        print('$TAG: 麦克风权限被拒绝');
        throw Exception('Cần quyền micro');
      }
    } else {
      // iOS/其他平台只请求麦克风权限
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        print('$TAG: 麦克风权限被拒绝');
        throw Exception('Cần quyền micro');
      }
    }

    // 检查是否可用
    print('$TAG: 检查PCM16编码是否支持');
    final isAvailable = await _audioRecorder.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );
    print('$TAG: PCM16编码支持状态: $isAvailable');

    // 设置音频模式 - 参考Android原生实现
    print('$TAG: 配置音频会话');
    final session = await AudioSession.instance;

    // 使用与原生Android实现更接近的配置
    if (Platform.isAndroid) {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
            flags: AndroidAudioFlags.audibilityEnforced,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientExclusive,
          androidWillPauseWhenDucked: false,
        ),
      );
    } else {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
        ),
      );
      await session.setActive(true);
    }

    _isRecorderInitialized = true;
    print('$TAG: 录音器初始化成功');
  }

  /// 初始化音频播放器
  // flutter_pcm_player 原生端只有一个 AudioTrack：创建/释放必须串行，
  // 否则旧实例的 release 会把刚建好的新 AudioTrack 一起释放（播放静默）
  static Future<void> _lifecycle = Future.value();
  // 每次 stopPlaying 递增，丢弃之前排队但尚未播放的音频帧
  static int _playGen = 0;

  static Future<void> _serial(Future<void> Function() op) {
    final next = _lifecycle.then((_) => op());
    _lifecycle = next.catchError((_) {});
    return next;
  }

  /// 确保播放器可用；已初始化则什么都不做
  static Future<void> initPlayer() => _serial(() async {
        if (_isPlayerInitialized && _pcmPlayer != null) return;
        await _initPlayerImpl();
      });

  static Future<void> _initPlayerImpl() async {
    // 确保任何旧播放器被释放
    await _releasePlayerImpl();

    try {
      print('$TAG: 使用简单方式初始化PCM播放器');

      // 创建新的播放器实例 - 完全按照官方示例的简单方式
      _pcmPlayer = PcmStreamPlayer();
      await _pcmPlayer!.initialize(sampleRate: _outputSampleRate);
      await _pcmPlayer!.play();

      _isPlayerInitialized = true;
      print('$TAG: PCM播放器初始化成功');
    } catch (e) {
      print('$TAG: PCM播放器初始化失败: $e');
      _isPlayerInitialized = false;
    }
  }

  /// 播放Opus音频数据
  static Future<void> playOpusData(Uint8List opusData) {
    final gen = _playGen;
    // 单帧最多 2s：任何一次初始化/写入卡住都不能让后面所有音频永远排队
    _playChain = _playChain.then(
      (_) => gen != _playGen
          ? Future<void>.value() // 已被 stopPlaying 打断
          : _playOpusFrame(opusData).timeout(
        const Duration(seconds: 2),
        onTimeout: () => print('$TAG: 播放一帧超时，跳过'),
      ),
    );
    return _playChain;
  }

  static Future<void> _playOpusFrame(Uint8List opusData) async {
    try {
      // 如果播放器未初始化，先初始化
      if (!_isPlayerInitialized || _pcmPlayer == null) {
        await initPlayer();
      }

      // 解码Opus数据
      // 空包 = 网络丢包：让解码器做丢包补偿（PLC）。
      // opus_dart 默认把“毫秒”当成采样数传给 opus_decode（BAD_ARG），
      // 所以显式给出一帧（60ms）的采样数。
      final Int16List pcmData;
      try {
        pcmData = opusData.isEmpty
            ? _decoder.decode(loss: _outputSampleRate * 60 ~/ 1000)
            : _decoder.decode(input: opusData);
      } catch (e) {
        // 单帧解码失败只丢这一帧；不要停播放器（会清空已缓冲的音频）
        print('$TAG: 解码失败，跳过一帧: $e');
        return;
      }

      // 准备PCM数据（小端）
      final Uint8List pcmBytes = Uint8List(pcmData.length * 2);
      ByteData bytes = ByteData.view(pcmBytes.buffer);
      for (int i = 0; i < pcmData.length; i++) {
        bytes.setInt16(i * 2, pcmData[i], Endian.little);
      }

      // 一段回答开头先攒 _startPrebuffer（见 beginReply）。
      // 服务器按实时速度发包，缓冲一旦被某次卡顿吃掉就再也涨不回来，
      // 之后每个小抖动都会变成断音；所以句中真断粮时重新攒 _rebuffer，
      // 把一串碎断音换成一次短停顿。
      // 长时间无音频（>2s）后又来数据，视为新的一段，重新攒开头。
      if (!_buffering) {
        final starved = DateTime.now().difference(_playbackEndsAt);
        if (starved > const Duration(seconds: 2)) {
          _buffering = true;
          _prebuffer = _startPrebuffer;
        } else if (starved > const Duration(milliseconds: 60)) {
          _buffering = true;
          _prebuffer = _rebuffer;
        }
      }
      if (_buffering) {
        _jitter.add(pcmBytes);
        if (_pcmDuration(_jitter.length) >= _prebuffer) {
          await _flushJitter();
        } else {
          // 句尾不足 _prebuffer 的部分也要按时播出
          _jitterFlushTimer?.cancel();
          _jitterFlushTimer = Timer(_prebuffer, () {
            _playChain = _playChain.then((_) => _flushJitter());
          });
        }
        return;
      }

      await _feed(pcmBytes);
    } catch (e) {
      print('$TAG: 播放失败: $e');

      // 简单重置并重新初始化
      await stopPlaying();
      await initPlayer();
    }
  }

  static Future<void> _flushJitter() async {
    _jitterFlushTimer?.cancel();
    _jitterFlushTimer = null;
    _buffering = false;
    if (_jitter.length == 0) return;
    await _feed(_jitter.takeBytes());
  }

  static Future<void> _feed(Uint8List pcmBytes) async {
    final now = DateTime.now();
    final starvedMs = now.difference(_playbackEndsAt).inMilliseconds;
    if (starvedMs > 20 && starvedMs < 2000) {
      // 数据来晚了：上一段已播完 starvedMs 毫秒才收到新数据（网络/服务器节奏）
      print('$TAG: 断粮 ${starvedMs}ms');
    }
    final base = _playbackEndsAt.isAfter(now) ? _playbackEndsAt : now;
    _playbackEndsAt = base.add(_pcmDuration(pcmBytes.length));
    if (_pcmPlayer != null) {
      await _pcmPlayer!.feed(pcmBytes);
    }
  }

  /// 停止播放
  /// 打断当前播放：丢弃排队帧并停止 AudioTrack，但保留播放器实例。
  /// （与原厂 Lily 一样整个通话只用一个 AudioTrack；反复 release/重建
  /// 会和插件里唯一的原生 AudioTrack 互相踩踏，导致静音）
  static Future<void> stopPlaying() {
    _playGen++;
    _playChain = Future.value();
    _jitterFlushTimer?.cancel();
    _jitterFlushTimer = null;
    _jitter.clear();
    _buffering = true;
    _prebuffer = _startPrebuffer;
    _playbackEndsAt = DateTime.now();
    return _serial(() async {
      final player = _pcmPlayer;
      if (player == null) return;
      try {
        await player.stop();
        await player.play();
        print('$TAG: 播放器已停止');
      } catch (e) {
        print('$TAG: 停止播放失败: $e，重建播放器');
        await _initPlayerImpl();
      }
    });
  }

  /// 彻底释放播放器（仅在不再需要播放时调用）
  static Future<void> releasePlayer() => _serial(_releasePlayerImpl);

  static Future<void> _releasePlayerImpl() async {
    final player = _pcmPlayer;
    _pcmPlayer = null;
    _isPlayerInitialized = false;
    if (player != null) {
      try {
        await player.stop();
        await player.release();
        _playbackEndsAt = DateTime.now();
        print('$TAG: 播放器已停止');
      } catch (e) {
        print('$TAG: 停止播放失败: $e');
      }
    }
  }

  /// 释放资源
  static Future<void> dispose() async {
    _audioStreamController.close();
    print('$TAG: 资源已释放');
  }

  /// 开始录音
  static Future<void> startRecording() async {
    if (!_isRecorderInitialized) {
      await initRecorder();
    }

    if (_isRecording) {
      // 标志可能已过期：麦克风被其他应用（如 com.sensornotes.xiaozhi）抢占后
      // 录音流会静默停止。以录音器的真实状态为准，必要时重启录音。
      bool reallyRecording = false;
      try {
        reallyRecording = await _audioRecorder.isRecording();
      } catch (_) {}
      if (reallyRecording &&
          _lastFrameAt != null &&
          DateTime.now().difference(_lastFrameAt!) <
              const Duration(seconds: 2)) {
        return;
      }
      print('$TAG: 录音标志已过期（无音频帧），重新启动录音');
      try {
        await _audioRecorder.stop();
      } catch (_) {}
      _isRecording = false;
    }

    try {
      print('$TAG: 尝试启动录音');

      // 确保麦克风权限已获取 - 使用不同方式检查权限
      final status = await Permission.microphone.status;
      print('$TAG: 麦克风权限状态: $status');

      if (status != PermissionStatus.granted) {
        final result = await Permission.microphone.request();
        print('$TAG: 请求麦克风权限结果: $result');
        if (result != PermissionStatus.granted) {
          print('$TAG: 麦克风权限被拒绝');
          return;
        }
      }

      // 尝试直接使用音频流
      try {
        print('$TAG: 尝试启动流式录音');
        final stream = await _audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: SAMPLE_RATE,
            numChannels: CHANNELS,
            // 与原厂 Lily 应用一致：MIC 音源 + 系统回声消除 + 降噪
            // （AcousticEchoCanceler / NoiseSuppressor 挂在录音会话上）。
            // 不开系统 AGC：安静时会把底噪放大，导致本地 VAD 一直判定在说话
            echoCancel: true,
            noiseSuppress: true,
            androidConfig: AndroidRecordConfig(
              audioSource: AndroidAudioSource.mic,
            ),
          ),
        );

        _isRecording = true;
        _pcmBuffer.clear();
        _channelPicker = PcmChannelPicker(
          expectedBytesPerSecond: SAMPLE_RATE * CHANNELS * 2,
        );
        print('$TAG: 流式录音启动成功');

        // 拼接成完整的60ms帧后再编码，避免截断或补零造成识别失真
        stream.listen(
          (data) async {
            if (data.isEmpty) return;
            _lastFrameAt = DateTime.now();
            final mono = _channelPicker!.process(
              data,
              DateTime.now().millisecondsSinceEpoch,
            );
            if (mono.isEmpty) return;
            if (!_loggedStride && PcmChannelPicker.detectedStride != null) {
              _loggedStride = true;
              print('$TAG: 麦克风交错声道数 ${PcmChannelPicker.detectedStride}');
            }
            _pcmBuffer.add(mono);
            if (_pcmBuffer.length < _frameBytes) return;
            final all = _pcmBuffer.takeBytes();
            int offset = 0;
            while (all.length - offset >= _frameBytes) {
              final frame = Uint8List.sublistView(
                all,
                offset,
                offset + _frameBytes,
              );
              offset += _frameBytes;
              final opusData = await encodeToOpus(frame);
              if (opusData != null) {
                _audioStreamController.add(opusData);
                if (_frameController.hasListener) {
                  _frameController.add(
                    VoiceFrame(
                      opusData,
                      VoiceActivityDetector.frameDb(frame),
                      VoiceActivityDetector.voicing(frame),
                    ),
                  );
                }
              }
            }
            if (offset < all.length) {
              _pcmBuffer.add(Uint8List.sublistView(all, offset));
            }
          },
          onError: (error) {
            print('$TAG: 音频流错误: $error');
            _isRecording = false;
          },
          onDone: () {
            print('$TAG: 音频流结束');
            _isRecording = false;
          },
        );
      } catch (e) {
        print('$TAG: 流式录音失败: $e');
        _isRecording = false;
        rethrow;
      }
    } catch (e, stackTrace) {
      print('$TAG: 启动录音失败: $e');
      print(stackTrace);
      _isRecording = false;
    }
  }

  /// 停止录音
  static Future<String?> stopRecording() async {
    if (!_isRecorderInitialized || !_isRecording) return null;

    // 取消定时器
    _audioProcessingTimer?.cancel();

    // 停止录音
    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;
      _pcmBuffer.clear();
      print('$TAG: 停止录音: $path');
      return path;
    } catch (e) {
      print('$TAG: 停止录音失败: $e');
      _isRecording = false;
      return null;
    }
  }

  /// 将PCM数据编码为Opus格式
  static Future<Uint8List?> encodeToOpus(Uint8List pcmData) async {
    try {
      // 删除频繁日志
      // 转换PCM数据为Int16List (小端字节序，与Android一致)
      final Int16List pcmInt16 = Int16List.fromList(
        List.generate(
          pcmData.length ~/ 2,
          (i) => (pcmData[i * 2]) | (pcmData[i * 2 + 1] << 8),
        ),
      );

      // 确保数据长度符合Opus要求（必须是2.5ms、5ms、10ms、20ms、40ms或60ms的采样数）
      final int samplesPerFrame = (SAMPLE_RATE * FRAME_DURATION) ~/ 1000;

      Uint8List encoded;

      // 处理过短的数据
      if (pcmInt16.length < samplesPerFrame) {
        // 对于过短的数据，可以通过添加静音来填充到所需长度
        final Int16List paddedData = Int16List(samplesPerFrame);
        for (int i = 0; i < pcmInt16.length; i++) {
          paddedData[i] = pcmInt16[i];
        }

        // 编码填充后的数据
        encoded = Uint8List.fromList(_encoder.encode(input: paddedData));
      } else {
        // 对于足够长的数据，裁剪到精确的帧长度
        encoded = Uint8List.fromList(
          _encoder.encode(input: pcmInt16.sublist(0, samplesPerFrame)),
        );
      }

      return encoded;
    } catch (e, stackTrace) {
      print('$TAG: Opus编码失败: $e');
      print(stackTrace);
      return null;
    }
  }

  /// 检查是否正在录音
  static bool get isRecording => _isRecording;

  /// 检查是否正在播放
  static bool get isPlaying => _isPlaying;
}
