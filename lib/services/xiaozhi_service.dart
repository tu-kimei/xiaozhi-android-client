import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart' show ValueNotifier, kDebugMode;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../services/xiaozhi_websocket_manager.dart';
import '../services/xiaozhi_mqtt_manager.dart';
import '../services/xiaozhi_ota_service.dart';
import '../utils/device_util.dart';
import '../utils/audio_util.dart';
import '../utils/voice_activity_detector.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 小智服务事件类型
enum XiaozhiServiceEventType {
  connected,
  disconnected,
  textMessage,
  audioData,
  error,
  voiceCallStart,
  voiceCallEnd,
  userMessage,
}

/// 小智服务事件
class XiaozhiServiceEvent {
  final XiaozhiServiceEventType type;
  final dynamic data;

  XiaozhiServiceEvent(this.type, this.data);
}

/// 小智服务监听器
typedef XiaozhiServiceListener = void Function(XiaozhiServiceEvent event);

/// 消息监听器
typedef MessageListener = void Function(dynamic message);

/// 机器人语音交互状态（用于界面显示"正在听/已停止听"）
enum XiaozhiVoiceState {
  idle, // 已停止听
  waiting, // 麦克风打开，等待有人开口（本地 VAD 未检测到语音）
  listening, // 正在听（检测到语音，正在上传）
  thinking, // 已停止听，等待服务器回答
  micBusy, // 麦克风没有数据（被其他应用占用）
  speaking, // 机器人正在说话
}

/// 小智服务
class XiaozhiService {
  static const String TAG = "XiaozhiService";
  static const String DEFAULT_SERVER = "wss://api.tenclass.net/xiaozhi/v1/";

  // 单例实例
  static XiaozhiService? _instance;

  String websocketUrl;
  final String macAddress;
  String token;
  final String otaUrl;
  final String clientId;
  String? _sessionId; // 会话ID将由服务器提供

  XiaozhiWebSocketManager? _webSocketManager;
  XiaozhiMqttManager? _mqttManager;
  XiaozhiOtaResult? _otaResult;
  bool _isConnected = false;
  bool _isMuted = false;
  final List<XiaozhiServiceListener> _listeners = [];
  StreamSubscription? _audioStreamSubscription;
  bool _isVoiceCallActive = false;
  WebSocketChannel? _ws;
  bool _hasStartedCall = false;
  MessageListener? _messageListener;

  // 机器人说话(TTS)时暂停上传麦克风，避免设备没有回声消除时听到自己的声音
  bool _micGateOpen = true;
  Timer? _resumeListenTimer;

  // —— 语音通话：本地 VAD 决定何时开始/停止听（manual 模式）——
  final VoiceActivityDetector _vad = VoiceActivityDetector();
  static const int _prerollFrames = 8; // 约 480ms，避免丢掉第一个字
  final List<Uint8List> _preroll = [];
  bool _utteranceActive = false;
  // 开口时会话已过期：先缓存音频，等 hello 后再补发
  bool _utterancePendingSession = false;
  bool _pendingUtteranceEnded = false;
  final List<Uint8List> _pendingFrames = [];
  Timer? _replyTimeout;
  // 当前这轮回答来自噪声幻听，丢弃其音频和文字
  bool _muteReply = false;
  // 每次 TTS 开始/结束递增，作废过期的“播完后恢复监听”回调
  int _drainToken = 0;

  /// 服务器 ASR（Whisper 类）对噪声常输出的固定幻听句
  static bool isNoiseHallucination(String text) {
    final t = text.toLowerCase();
    return t.contains('subscribe') ||
        t.contains('video hấp dẫn') ||
        t.contains('đăng ký kênh') ||
        t.contains('ghiền mì gõ') ||
        t.contains('cảm ơn các bạn đã theo dõi') ||
        t.contains('hẹn gặp lại các bạn trong') ||
        t.contains('la la school') ||
        t.contains('thực hiện hành động này trên youtube') ||
        t.contains('kênh youtube');
  }
  Timer? _micWatchdog;
  int _vadLogCounter = 0;
  // 调试：保存最近一句上传的 Opus 帧，便于离线检查（仅 debug 构建）
  final List<Uint8List> _debugUtterance = [];

  /// 当前语音交互状态，界面通过 ValueListenableBuilder 监听
  final ValueNotifier<XiaozhiVoiceState> voiceState = ValueNotifier(
    XiaozhiVoiceState.idle,
  );

  /// 工厂构造函数，实现单例模式
  factory XiaozhiService({
    required String websocketUrl,
    required String macAddress,
    required String token,
    String otaUrl = '',
    String clientId = '',
    String? sessionId,
  }) {
    // 配置变化时重建实例，避免沿用旧的服务器地址/Token
    final old = _instance;
    if (old != null &&
        (old.macAddress != macAddress ||
            old.otaUrl != otaUrl ||
            old.clientId != clientId ||
            (otaUrl.isEmpty &&
                (old.websocketUrl != websocketUrl || old.token != token)))) {
      old.disconnect();
      _instance = null;
    }
    _instance ??= XiaozhiService._internal(
      websocketUrl: websocketUrl,
      macAddress: macAddress,
      token: token,
      otaUrl: otaUrl,
      clientId: clientId,
      sessionId: sessionId,
    );
    return _instance!;
  }

  /// 内部构造函数
  XiaozhiService._internal({
    required this.websocketUrl,
    required this.macAddress,
    required this.token,
    this.otaUrl = '',
    this.clientId = '',
    String? sessionId,
  }) {
    _sessionId = sessionId;
    _init();
  }

  /// 获取实例
  static XiaozhiService? get instance => _instance;

  /// 切换到语音通话模式
  Future<void> switchToVoiceCallMode() async {
    // 如果已经在语音通话模式，直接返回
    if (_isVoiceCallActive) return;

    try {
      print('$TAG: 正在切换到语音通话模式');

      // 简化初始化流程，确保干净状态
      await AudioUtil.stopPlaying();
      await AudioUtil.initRecorder();
      await AudioUtil.initPlayer();

      _isVoiceCallActive = true;
      print('$TAG: 已切换到语音通话模式');
    } catch (e) {
      print('$TAG: 切换到语音通话模式失败: $e');
      rethrow;
    }
  }

  /// 切换到普通聊天模式
  Future<void> switchToChatMode() async {
    // 如果已经在普通聊天模式，直接返回
    if (!_isVoiceCallActive) return;

    try {
      print('$TAG: 正在切换到普通聊天模式');

      // 停止语音通话相关的活动
      await stopListeningCall();

      // 确保播放器停止
      await AudioUtil.stopPlaying();

      _isVoiceCallActive = false;
      print('$TAG: 已切换到普通聊天模式');
    } catch (e) {
      print('$TAG: 切换到普通聊天模式失败: $e');
      _isVoiceCallActive = false;
    }
  }

  /// 初始化
  Future<void> _init() async {
    // 使用配置中的MAC地址作为设备ID
    print('$TAG: 初始化完成，使用MAC地址作为设备ID: $macAddress');

    // 初始化音频工具
    await AudioUtil.initRecorder();
    await AudioUtil.initPlayer();
  }

  /// 设置消息监听器
  void setMessageListener(MessageListener listener) {
    _messageListener = listener;
  }

  /// 添加事件监听器
  void addListener(XiaozhiServiceListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除事件监听器
  void removeListener(XiaozhiServiceListener listener) {
    _listeners.remove(listener);
  }

  /// 分发事件到所有监听器
  void _dispatchEvent(XiaozhiServiceEvent event) {
    // 复制一份再遍历，监听器可能在回调中移除自己
    for (var listener in List.of(_listeners)) {
      listener(event);
    }
  }

  /// 当前控制通道是否已连接（MQTT 或 WebSocket）
  bool get _channelConnected =>
      (_mqttManager?.isConnected ?? false) ||
      (_webSocketManager?.isConnected ?? false);

  /// 通过当前控制通道发送 JSON 消息
  void _sendControlMessage(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    if (_mqttManager != null) {
      _mqttManager!.sendMessage(encoded);
    } else {
      _webSocketManager?.sendMessage(encoded);
    }
  }

  /// 发送音频分片（MQTT 模式下音频走 UDP，暂不处理）
  void _sendAudioChunk(List<int> data) {
    if (_mqttManager != null) {
      _mqttManager!.sendBinaryMessage(data);
    } else {
      _webSocketManager?.sendBinaryMessage(data);
    }
  }

  /// 通过OTA获取最新的连接配置（仅OTA模式）
  Future<void> _refreshFromOta() async {
    if (otaUrl.isEmpty) {
      _otaResult = null;
      return;
    }
    final result = await XiaozhiOtaService.checkVersion(
      otaUrl: otaUrl,
      macAddress: macAddress,
      clientId: clientId,
    );
    if (result.needsActivation) {
      throw Exception(
        'Thiết bị chưa được kích hoạt. Vào Cài đặt > Xiaozhi để kích hoạt (mã ${result.activationCode})',
      );
    }
    _otaResult = result;
    if (result.websocketUrl != null && result.websocketUrl!.isNotEmpty) {
      websocketUrl = result.websocketUrl!;
    }
    if (result.websocketToken != null) {
      token = result.websocketToken!;
    }
  }

  /// 是否使用 MQTT 控制通道
  /// 官方服务器对已绑定设备只接受 MQTT + UDP（WebSocket 会在 hello 后被关闭）
  bool get _useMqtt => otaUrl.isNotEmpty && (_otaResult?.hasMqtt ?? false);

  /// 建立 MQTT 连接
  Future<void> _connectMqtt() async {
    final result = _otaResult!;
    await _mqttManager?.disconnect();

    final manager = XiaozhiMqttManager(
      deviceId: macAddress,
      clientId: clientId,
    );
    manager.addListener(_onWebSocketEvent);
    _mqttManager = manager;

    await manager.connect(
      endpoint: result.mqttEndpoint!,
      mqttClientId: result.mqttClientId!,
      username: result.mqttUsername!,
      password: result.mqttPassword!,
      publishTopic: result.mqttPublishTopic,
      subscribeTopic: result.mqttSubscribeTopic,
    );
  }

  /// 建立 WebSocket 连接
  Future<void> _connectWebSocket() async {
    await _webSocketManager?.disconnect();

    _webSocketManager = XiaozhiWebSocketManager(
      deviceId: macAddress,
      clientId: clientId,
      enableToken: true,
    );
    _webSocketManager!.addListener(_onWebSocketEvent);
    await _webSocketManager!.connect(websocketUrl, token);
  }

  /// 连接到小智服务
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      print('$TAG: 开始连接服务器...');
      await _refreshFromOta();

      if (_useMqtt) {
        print('$TAG: 使用 MQTT + UDP 通道');
        await _connectMqtt();
      } else {
        print('$TAG: 使用 WebSocket 通道');
        await _connectWebSocket();
      }
    } catch (e) {
      print('$TAG: 连接失败: $e');
      _dispatchEvent(
        XiaozhiServiceEvent(
          XiaozhiServiceEventType.error,
          'Kết nối Xiaozhi thất bại: $e',
        ),
      );
    }
  }

  /// 断开小智服务连接
  Future<void> disconnect() async {
    try {
      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止音频录制
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
      }

      // 断开 MQTT 连接
      await _mqttManager?.disconnect();
      _mqttManager = null;

      // 断开 WebSocket 连接
      await _webSocketManager?.disconnect();
      _webSocketManager = null;

      _isConnected = false;
    } catch (e) {
      print('$TAG: 断开连接失败: $e');
    }
  }

  /// 发送文本消息
  Future<String> sendTextMessage(String message) async {
    if (!isConnected) {
      await connect();
    }

    try {
      // 创建一个Completer来等待响应
      final completer = Completer<String>();
      bool hasResponse = false;

      print('$TAG: 开始发送文本消息: $message');

      // 添加消息监听器，监听所有可能的回复
      void onceListener(XiaozhiServiceEvent event) {
        if (event.type == XiaozhiServiceEventType.textMessage) {
          // 忽略echo消息（即我们发送的消息）
          if (event.data == message) {
            print('$TAG: 忽略echo消息: ${event.data}');
            return;
          }

          print('$TAG: 收到服务器响应: ${event.data}');
          if (!completer.isCompleted) {
            hasResponse = true;
            completer.complete(event.data as String);
            removeListener(onceListener);
          }
        } else if (event.type == XiaozhiServiceEventType.error &&
            !completer.isCompleted) {
          print('$TAG: 收到错误响应: ${event.data}');
          completer.completeError(event.data.toString());
          removeListener(onceListener);
        }
      }

      // 先添加监听器，确保不会错过任何消息
      addListener(onceListener);

      // 发送文本请求
      print('$TAG: 发送文本请求: $message');
      if (_mqttManager != null) {
        _mqttManager!.sendTextRequest(message);
      } else {
        _webSocketManager!.sendTextRequest(message);
      }

      // 设置超时，15秒比10秒更宽松一些
      final timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          print('$TAG: 请求超时，15秒内没有收到响应');
          completer.completeError('Hết thời gian chờ');
          removeListener(onceListener);
        }
      });

      // 等待响应
      try {
        final result = await completer.future;
        // 取消超时定时器
        timeoutTimer.cancel();
        return result;
      } catch (e) {
        // 取消超时定时器
        timeoutTimer.cancel();
        rethrow;
      }
    } catch (e) {
      print('$TAG: 发送消息失败: $e');
      rethrow;
    }
  }

  /// 连接语音通话
  Future<void> connectVoiceCall() async {
    try {
      // 简化流程，确保权限和音频准备就绪
      if (Platform.isIOS || Platform.isAndroid) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          print('$TAG: 麦克风权限被拒绝');
          _dispatchEvent(
            XiaozhiServiceEvent(
              XiaozhiServiceEventType.error,
              'Quyền micro bị từ chối',
            ),
          );
          return;
        }
      }

      // 初始化音频系统
      await AudioUtil.stopPlaying();
      await AudioUtil.initRecorder();
      await AudioUtil.initPlayer();

      await _refreshFromOta();

      if (_useMqtt) {
        print('$TAG: 使用 MQTT 通道（语音音频需 UDP，暂未实现）');
        await _connectMqtt();
      } else {
        print('$TAG: 正在连接 $websocketUrl');
        print('$TAG: 设备ID: $macAddress');
        print('$TAG: Token启用: true');
        print('$TAG: 使用Token: $token');
        await _connectWebSocket();
      }
    } catch (e) {
      print('$TAG: 连接失败: $e');
      rethrow;
    }
  }

  /// 结束语音通话
  Future<void> disconnectVoiceCall() async {
    if (_mqttManager == null && _webSocketManager == null) return;

    try {
      // 停止音频录制
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
      }

      // 停止音频播放
      await AudioUtil.stopPlaying();

      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 直接断开连接
      await disconnect();
    } catch (e) {
      // 忽略断开连接时的错误
      print('$TAG: 结束语音通话时发生错误: $e');
    }
  }

  /// 开始说话
  Future<void> startSpeaking() async {
    try {
      final message = {'type': 'speak', 'state': 'start', 'mode': 'auto'};
      _sendControlMessage(message);
      print('$TAG: 已发送开始说话消息');
    } catch (e) {
      print('$TAG: 开始说话失败: $e');
    }
  }

  /// 停止说话
  Future<void> stopSpeaking() async {
    try {
      final message = {'type': 'speak', 'state': 'stop', 'mode': 'auto'};
      _sendControlMessage(message);
      print('$TAG: 已发送停止说话消息');
    } catch (e) {
      print('$TAG: 停止说话失败: $e');
    }
  }

  /// 发送listen消息
  void _sendListenMessage() async {
    try {
      final listenMessage = {
        'type': 'listen',
        'session_id': _sessionId,
        'state': 'start',
        'mode': 'auto',
      };
      _sendControlMessage(listenMessage);
      print('$TAG: 已发送listen消息');

      // 开始录音
      _isVoiceCallActive = true;
      await AudioUtil.startRecording();
    } catch (e) {
      print('$TAG: 发送listen消息失败: $e');
      _dispatchEvent(
        XiaozhiServiceEvent(
          XiaozhiServiceEventType.error,
          'Gửi tin nhắn listen thất bại: $e',
        ),
      );
    }
  }

  /// 开始听说（语音通话模式）
  Future<void> startListeningCall() async {
    try {
      // 确保已经有会话ID
      if (_sessionId == null) {
        print('$TAG: 没有会话ID，无法开始监听，等待会话ID初始化...');
        // 等待短暂时间，然后重新检查会话ID
        await Future.delayed(const Duration(milliseconds: 500));
        if (_sessionId == null) {
          print('$TAG: 会话ID仍然为空，放弃开始监听');
          throw Exception('Thiếu ID phiên, không thể ghi âm');
        }
      }

      print('$TAG: 使用会话ID开始录音: $_sessionId');

      // 请求麦克风权限
      if (Platform.isIOS) {
        final micStatus = await Permission.microphone.status;
        if (micStatus != PermissionStatus.granted) {
          final result = await Permission.microphone.request();
          if (result != PermissionStatus.granted) {
            print('$TAG: 麦克风权限被拒绝');
            _dispatchEvent(
              XiaozhiServiceEvent(
                XiaozhiServiceEventType.error,
                'Quyền micro bị từ chối',
              ),
            );
            return;
          }
        }

        // 确保音频会话已初始化
        await AudioUtil.initRecorder();
      } else {
        // Android权限请求
        final status = await Permission.microphone.request();
        if (status.isDenied) {
          print('$TAG: 麦克风权限被拒绝');
          _dispatchEvent(
            XiaozhiServiceEvent(
              XiaozhiServiceEventType.error,
              'Quyền micro bị từ chối',
            ),
          );
          return;
        }
      }

      // 开始录音
      _isVoiceCallActive = true;
      await AudioUtil.startRecording();

      // 设置音频帧订阅（避免重复订阅导致音频重复发送）
      _audioStreamSubscription ??= AudioUtil.frameStream.listen(_onVoiceFrame);

      if (_mqttManager != null && !_mqttManager!.hasSession) {
        _mqttManager!.ensureSession();
      }
      _resumeWaiting();
      _startMicWatchdog();
      print('$TAG: 语音通话开始，本地 VAD 等待说话');
    } catch (e) {
      print('$TAG: 开始监听失败: $e');
      throw Exception('Bắt đầu nhập giọng nói thất bại: $e');
    }
  }

  /// 通话中每 3 秒检查麦克风是否还有数据；没有则重启录音，仍失败则提示
  void _startMicWatchdog() {
    _micWatchdog?.cancel();
    _micWatchdog = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_inVoiceCall) return;
      final last = AudioUtil.lastFrameAt;
      final stale =
          last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 3);
      if (!stale) {
        if (voiceState.value == XiaozhiVoiceState.micBusy) _resumeWaiting();
        return;
      }
      print('$TAG: 麦克风 3 秒无数据，尝试重启录音');
      await AudioUtil.startRecording();
      await Future.delayed(const Duration(milliseconds: 800));
      final again = AudioUtil.lastFrameAt;
      if (again == null ||
          DateTime.now().difference(again) > const Duration(seconds: 2)) {
        print('$TAG: 麦克风仍无数据，可能被其他应用占用');
        voiceState.value = XiaozhiVoiceState.micBusy;
      }
    });
  }

  /// 断句交给服务器 VAD（listen mode=auto，与原厂 Lily 应用相同）：
  /// 等待期间持续上传麦克风，服务器判断说完后回 stt。
  /// 本地 VAD 仅用于界面显示“正在听”。设为 false 回到本地 VAD + manual。
  static const bool _serverVad = true;

  /// 已向服务器发送 listen start(auto)，正在持续上传
  bool _autoStreaming = false;

  /// 服务器因空闲结束了会话：不主动重连（否则服务器每分钟说一句告别语），
  /// 等本地 VAD 听到有人开口再握手
  bool _idleClosed = false;

  /// 本地 VAD 触发重新握手后，若迟迟没有识别结果（多半是噪声），主动结束会话
  Timer? _probeTimer;

  /// [seconds] 内没有新的识别结果就静默结束会话：
  /// 噪声误触发握手后 15s；一轮回答结束后 30s（否则服务器空闲 1 分钟会自己说告别语）
  void _armProbe({int seconds = 15}) {
    _probeTimer?.cancel();
    _probeTimer = Timer(Duration(seconds: seconds), () {
      if (!_inVoiceCall || voiceState.value == XiaozhiVoiceState.speaking) {
        return;
      }
      print('$TAG: $seconds 秒无识别结果，静默结束会话');
      if (kDebugMode) _dumpDebugUtterance();
      _autoStreaming = false;
      _idleClosed = true;
      _mqttManager?.closeSession();
    });
  }

  void _startAutoListen({bool userSpoke = false}) {
    if (!_serverVad || !_inVoiceCall || !_micGateOpen) return;
    if (userSpoke && _idleClosed) {
      print('$TAG: 本地 VAD 听到开口，重新握手');
      _idleClosed = false;
      _armProbe();
    }
    if (!_sessionReady) {
      if (_idleClosed) return;
      _mqttManager?.ensureSession(); // hello 后再开始
      return;
    }
    _sendListen('start', mode: 'auto');
    _autoStreaming = true;
    if (kDebugMode) {
      _debugUtterance
        ..clear()
        ..addAll(_preroll);
    }
    // 握手期间缓存的开头音频先补发
    for (final f in _preroll) {
      _sendAudioChunk(f);
    }
    _preroll.clear();
  }

  bool get _sessionReady =>
      _mqttManager == null ? _channelConnected : _mqttManager!.hasSession;

  bool get _inVoiceCall =>
      _isVoiceCallActive && _audioStreamSubscription != null;

  /// 重新进入"等待开口"状态（麦克风打开，但不上传）
  void _resumeWaiting() {
    _replyTimeout?.cancel();
    _vad.reset();
    _preroll.clear();
    _utteranceActive = false;
    _micGateOpen = true;
    _autoStreaming = false;
    voiceState.value = XiaozhiVoiceState.waiting;
    _startAutoListen();
    if (_serverVad && _sessionReady) _armProbe(seconds: 30);
  }

  void _sendListen(String state, {String mode = 'manual'}) {
    _sendControlMessage({
      'session_id': _sessionId,
      'type': 'listen',
      'state': state,
      'mode': mode,
    });
  }

  /// 处理一帧麦克风音频：本地 VAD 判断开口 / 说完
  void _onVoiceFrame(VoiceFrame frame) {
    if (!_micGateOpen) return;
    final event = _vad.process(frame.db, voicing: frame.voicing);
    if (++_vadLogCounter % 50 == 0) {
      print(
        '$TAG: VAD 音量 ${frame.db.toStringAsFixed(1)}dB, '
        '底噪 ${_vad.noiseDb.toStringAsFixed(1)}dB, '
        '阈值 ${_vad.thresholdDb.toStringAsFixed(1)}dB, '
        '浊音度 ${frame.voicing.toStringAsFixed(2)}',
      );
    }

    if (_serverVad) {
      // 本地 VAD 只驱动界面；音频全部上传，由服务器断句
      if (event == VadEvent.speechStart) {
        voiceState.value = XiaozhiVoiceState.listening;
        if (!_autoStreaming) _startAutoListen(userSpoke: true);
      } else if (event == VadEvent.speechEnd &&
          voiceState.value == XiaozhiVoiceState.listening) {
        voiceState.value = XiaozhiVoiceState.waiting;
      }
      if (_autoStreaming) {
        _sendAudioChunk(frame.opus);
        if (kDebugMode && _debugUtterance.length < 500) {
          _debugUtterance.add(frame.opus);
        }
      } else {
        // 会话还没就绪：保留最近约 1.5s，握手后补发
        _preroll.add(frame.opus);
        if (_preroll.length > 25) _preroll.removeAt(0);
      }
      return;
    }

    if (!_utteranceActive) {
      _preroll.add(frame.opus);
      if (_preroll.length > _prerollFrames) _preroll.removeAt(0);
      if (event == VadEvent.speechStart) _beginUtterance();
      return;
    }

    if (kDebugMode) _debugUtterance.add(frame.opus);
    if (_utterancePendingSession) {
      _pendingFrames.add(frame.opus);
    } else {
      _sendAudioChunk(frame.opus);
    }
    if (event == VadEvent.speechEnd) _endUtterance();
  }

  void _beginUtterance() {
    print(
      '$TAG: VAD 检测到说话 (底噪 ${_vad.noiseDb.toStringAsFixed(1)}dB, '
      '阈值 ${_vad.thresholdDb.toStringAsFixed(1)}dB)',
    );
    _utteranceActive = true;
    voiceState.value = XiaozhiVoiceState.listening;
    final buffered = List<Uint8List>.from(_preroll);
    _preroll.clear();
    if (kDebugMode) {
      _debugUtterance
        ..clear()
        ..addAll(buffered);
    }
    if (_sessionReady) {
      _sendListen('start');
      for (final f in buffered) {
        _sendAudioChunk(f);
      }
    } else {
      // 会话过期：先握手，hello 后补发
      _utterancePendingSession = true;
      _pendingUtteranceEnded = false;
      _pendingFrames
        ..clear()
        ..addAll(buffered);
      _mqttManager?.ensureSession();
    }
  }

  void _endUtterance() {
    print(
      '$TAG: VAD 说话结束，停止听 (${_debugUtterance.length} 帧, '
      '约 ${_debugUtterance.length * 60}ms)',
    );
    if (kDebugMode) _dumpDebugUtterance();
    _utteranceActive = false;
    _micGateOpen = false; // 等机器人回答完再听
    voiceState.value = XiaozhiVoiceState.thinking;
    if (_utterancePendingSession) {
      _pendingUtteranceEnded = true;
    } else {
      _sendListen('stop');
    }
    _armReplyTimeout();
  }

  /// 服务器没回答（没听清/被中断）时自动回到等待状态
  void _armReplyTimeout() {
    _replyTimeout?.cancel();
    _replyTimeout = Timer(const Duration(seconds: 10), () {
      if (_inVoiceCall && voiceState.value != XiaozhiVoiceState.speaking &&
          !_micGateOpen) {
        print('$TAG: 10 秒内无回答，重新等待说话');
        _resumeWaiting();
      }
    });
  }

  Future<void> _dumpDebugUtterance() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final b = BytesBuilder();
      for (final f in _debugUtterance) {
        b.add([f.length >> 8, f.length & 0xFF]);
        b.add(f);
      }
      await File('${dir.path}/last_utterance.bin').writeAsBytes(b.takeBytes());
    } catch (e) {
      print('$TAG: 保存调试语句失败: $e');
    }
  }

  /// hello 后补发会话过期期间缓存的语句
  void _flushPendingUtterance() {
    if (!_utterancePendingSession) return;
    _utterancePendingSession = false;
    _sendListen('start');
    for (final f in _pendingFrames) {
      _sendAudioChunk(f);
    }
    _pendingFrames.clear();
    if (_pendingUtteranceEnded) {
      _pendingUtteranceEnded = false;
      _sendListen('stop');
    }
  }

  /// 停止听说（语音通话模式）
  Future<void> stopListeningCall() async {
    _micWatchdog?.cancel();
    _resumeListenTimer?.cancel();
    _replyTimeout?.cancel();
    _utteranceActive = false;
    _utterancePendingSession = false;
    _pendingFrames.clear();
    voiceState.value = XiaozhiVoiceState.idle;
    try {
      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送停止监听命令
      if (_sessionId != null && _channelConnected) {
        final message = {
          'session_id': _sessionId,
          'type': 'listen',
          'state': 'stop',
          'mode': 'auto',
        };
        _sendControlMessage(message);
        print('$TAG: 已发送停止监听消息 (语音通话模式)');
      }
    } catch (e) {
      print('$TAG: 停止监听失败: $e');
    }
  }

  /// 取消发送（上滑取消）
  Future<void> abortListening() async {
    voiceState.value = XiaozhiVoiceState.idle;
    try {
      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送中止命令
      if (_sessionId != null && _channelConnected) {
        final message = {'session_id': _sessionId, 'type': 'abort'};
        _sendControlMessage(message);
        print('$TAG: 已发送中止消息');
      }
    } catch (e) {
      print('$TAG: 中止监听失败: $e');
    }
  }

  /// 切换静音状态
  void toggleMute() {
    _isMuted = !_isMuted;

    if (!_channelConnected) return;

    try {
      final request = {'type': _isMuted ? 'voice_mute' : 'voice_unmute'};

      _sendControlMessage(request);
    } catch (e) {
      print('$TAG: 切换静音状态失败: $e');
    }
  }

  /// 处理WebSocket事件
  void _onWebSocketEvent(XiaozhiEvent event) {
    switch (event.type) {
      case XiaozhiEventType.connected:
        _isConnected = true;
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.connected, null),
        );
        break;

      case XiaozhiEventType.disconnected:
        _isConnected = false;
        voiceState.value = XiaozhiVoiceState.idle;
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.disconnected, null),
        );
        break;

      case XiaozhiEventType.message:
        _handleTextMessage(event.data as String);
        break;

      case XiaozhiEventType.binaryMessage:
        // 处理二进制音频数据 - 简化直接播放
        final audioData = event.data as List<int>;
        // 对误识别（噪声幻听）的回答不播放
        if (_muteReply) break;
        AudioUtil.playOpusData(Uint8List.fromList(audioData));
        break;

      case XiaozhiEventType.error:
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.error, event.data),
        );
        break;
    }
  }

  /// 处理WebSocket消息
  void _handleWebSocketMessage(dynamic message) {
    try {
      if (message is String) {
        _handleTextMessage(message);
      } else if (message is List<int>) {
        AudioUtil.playOpusData(Uint8List.fromList(message));
      }
    } catch (e) {
      print('$TAG: 处理消息失败: $e');
    }
  }

  /// 处理文本消息
  void _handleTextMessage(String message) {
    print('$TAG: 收到文本消息: $message');
    try {
      final Map<String, dynamic> jsonData = json.decode(message);
      final String type = jsonData['type'] ?? '';

      // 确保首先调用消息监听器
      if (_messageListener != null) {
        _messageListener!(jsonData);
      }

      // 更新会话ID（服务器在hello消息中会提供新的会话ID）
      if (jsonData['session_id'] != null) {
        _sessionId = jsonData['session_id'];
        print('$TAG: 更新会话ID: $_sessionId');
      }

      // 根据消息类型分发事件
      switch (type) {
        case 'hello':
          // 服务器下行音频参数（官方服务器TTS为24000Hz）
          final params = jsonData['audio_params'];
          if (params is Map && params['sample_rate'] is int) {
            AudioUtil.setOutputSampleRate(params['sample_rate'] as int);
          }
          // 会话过期期间开口说的话，hello 后补发
          if (_inVoiceCall) {
            _flushPendingUtterance();
            _startAutoListen();
          }
          break;

        case 'goodbye':
          if (_inVoiceCall) {
            // 会话超时结束：不立即重新握手（否则空闲时每分钟被服务器踢一次），
            // 下次开口时 _beginUtterance 会先缓存音频再握手
            _autoStreaming = false;
            if (voiceState.value == XiaozhiVoiceState.thinking) {
              _resumeWaiting();
            } else if (_serverVad) {
              // 空闲超时被结束：先别重连，等有人开口（见 _idleClosed）
              _idleClosed = true;
            }
          } else {
            voiceState.value = XiaozhiVoiceState.idle;
          }
          break;

        case 'start':
          // 收到start响应后，如果是语音通话模式，开始录音
          if (_isVoiceCallActive) {
            _sendListenMessage();
          }
          break;

        case 'tts':
          // TTS消息处理
          final String state = jsonData['state'] ?? '';
          final String text = jsonData['text'] ?? '';

          if (state == 'start') {
            // 机器人开始说话：暂停上传麦克风
            _autoStreaming = false;
            _drainToken++;
            AudioUtil.beginReply();
            _resumeListenTimer?.cancel();
            _replyTimeout?.cancel();
            _micGateOpen = false;
            if (_utteranceActive) {
              // 机器人主动说话时放弃当前语句
              _utteranceActive = false;
              _vad.reset();
            }
            voiceState.value = XiaozhiVoiceState.speaking;
          } else if (state == 'stop') {
            // _muteReply 保持到下一句真实识别结果：abort 之后服务器常常
            // 还会接着说“Tạm biệt nhé!”之类的告别语，也不能播出来
            // 说完后等待播放缓冲排空，再进入下一轮监听
            _resumeListenTimer?.cancel();
            final inCall =
                _isVoiceCallActive && _audioStreamSubscription != null;
            // 等排队中的音频真正播完，再留 700ms 让喇叭余音/房间回声散去，
            // 否则麦克风会把机器人自己的话录进去
            final token = ++_drainToken;
            final stopAt = DateTime.now();
            final left = AudioUtil.remainingPlayback;
            AudioUtil.whenPlaybackDrained().then((_) {
              print('$TAG: 播放排空用时 '
                  '${DateTime.now().difference(stopAt).inMilliseconds}ms'
                  '（tts stop 时估计剩余 ${left.inMilliseconds}ms）');
              if (token != _drainToken) return;
              _resumeListenTimer?.cancel();
              _resumeListenTimer = Timer(
                const Duration(milliseconds: 700),
                () {
                  if (token != _drainToken) return;
                  if (inCall && _inVoiceCall) {
                    _resumeWaiting();
                  } else if (voiceState.value ==
                      XiaozhiVoiceState.speaking) {
                    voiceState.value = XiaozhiVoiceState.idle;
                  }
                },
              );
            });
          }

          if (state == 'sentence_start' && text.isNotEmpty && !_muteReply) {
            print('$TAG: 收到TTS句子: $text');
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.textMessage, text),
            );
          }
          break;

        case 'stt':
          // 处理语音识别结果
          final String text = jsonData['text'] ?? '';
          if (isNoiseHallucination(text)) {
            // 服务器 ASR 把背景噪声“听”成了视频片尾语：中断回答，继续等待
            print('$TAG: 忽略噪声幻听识别结果: $text');
            _muteReply = true;
            _micGateOpen = false; // 服务器这一轮已结束监听，回答被丢弃后再重新开始
            _autoStreaming = false;
            _sendControlMessage({'session_id': _sessionId, 'type': 'abort'});
            _armReplyTimeout(); // 若服务器不再发 tts stop，也要回到监听
            break;
          }
          _muteReply = false;
          if (text.isNotEmpty) {
            // 服务器已识别出一句话：停止上传，等待回答
            _probeTimer?.cancel();
            _micGateOpen = false;
            _autoStreaming = false;
            voiceState.value = XiaozhiVoiceState.thinking;
            _armReplyTimeout();
            print('$TAG: 收到语音识别结果: $text');
            // 先分发用户消息事件
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.userMessage, text),
            );
          }
          break;

        case 'emotion':
          // 处理表情消息
          final String emotion = jsonData['emotion'] ?? '';
          if (emotion.isNotEmpty) {
            print('$TAG: 收到表情消息: $emotion');
            _dispatchEvent(
              XiaozhiServiceEvent(
                XiaozhiServiceEventType.textMessage,
                'Cảm xúc: $emotion',
              ),
            );
          }
          break;

        default:
          // 对于其他类型的消息，直接忽略
          print('$TAG: 收到未知类型消息: $type, 原始数据: $message');
      }
    } catch (e) {
      print('$TAG: 解析消息失败: $e, 原始消息: $message');
    }
  }

  /// 开始通话
  void _startCall() {
    try {
      // 发送开始通话消息
      final startMessage = {
        'type': 'start',
        'mode': 'auto',
        'audio_params': {
          'format': 'opus',
          'sample_rate': 16000,
          'channels': 1,
          'frame_duration': 60,
        },
      };
      _sendControlMessage(startMessage);
      print('$TAG: 已发送开始通话消息');
    } catch (e) {
      print('$TAG: 开始通话失败: $e');
    }
  }

  /// 中断音频播放
  Future<void> stopPlayback() async {
    try {
      print('$TAG: 正在停止音频播放');

      // 简单直接地停止播放
      await AudioUtil.stopPlaying();

      print('$TAG: 音频播放已停止');
    } catch (e) {
      print('$TAG: 停止音频播放失败: $e');
    }
  }

  /// 判断是否已连接
  bool get isConnected => _isConnected && _channelConnected;

  /// 判断是否静音
  bool get isMuted => _isMuted;

  /// 判断语音通话是否活跃
  bool get isVoiceCallActive => _isVoiceCallActive;

  /// 释放资源
  Future<void> dispose() async {
    await disconnect();
    await AudioUtil.dispose();
    _listeners.clear();
    print('$TAG: 资源已释放');
  }

  /// 开始监听（按住说话模式）
  Future<void> startListening({String mode = 'manual'}) async {
    if (!isConnected) {
      await connect();
    }

    try {
      // 确保已经有会话ID
      if (_sessionId == null) {
        print('$TAG: 没有会话ID，无法开始监听');
        return;
      }

      // 开始录音
      await AudioUtil.startRecording();

      // 发送开始监听命令
      final message = {
        'session_id': _sessionId,
        'type': 'listen',
        'state': 'start',
        'mode': mode,
      };
      _sendControlMessage(message);
      voiceState.value = XiaozhiVoiceState.listening;
      print('$TAG: 已发送开始监听消息 (按住说话)');

      // 设置音频流订阅
      _audioStreamSubscription = AudioUtil.audioStream.listen((opusData) {
        // 发送音频数据
        _sendAudioChunk(opusData);
      });
    } catch (e) {
      print('$TAG: 开始监听失败: $e');
      throw Exception('Bắt đầu nhập giọng nói thất bại: $e');
    }
  }

  /// 停止监听（按住说话模式）
  Future<void> stopListening() async {
    try {
      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送停止监听命令
      if (_sessionId != null && _channelConnected) {
        final message = {
          'session_id': _sessionId,
          'type': 'listen',
          'state': 'stop',
        };
        _sendControlMessage(message);
        voiceState.value = XiaozhiVoiceState.thinking;
        print('$TAG: 已发送停止监听消息');
      }
    } catch (e) {
      print('$TAG: 停止监听失败: $e');
    }
  }

  /// 发送中断消息
  Future<void> sendAbortMessage() async {
    try {
      if (_isConnected && _sessionId != null) {
        final abortMessage = {
          'session_id': _sessionId,
          'type': 'abort',
          'reason': 'wake_word_detected',
        };
        _sendControlMessage(abortMessage);
        print('$TAG: 发送中断消息: $abortMessage');

        // 如果当前正在录音，短暂停顿后继续
        if (_isSpeaking) {
          await stopListeningCall();
          await Future.delayed(const Duration(milliseconds: 500));
          await startListeningCall();
        }
      }
    } catch (e) {
      print('$TAG: 发送中断消息失败: $e');
    }
  }

  /// 判断是否正在说话
  bool get _isSpeaking => _audioStreamSubscription != null;
}
