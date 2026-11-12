import 'dart:async';
import 'package:flutter/material.dart';
import '../services/face_controller.dart';
import '../services/robot_preferences.dart';
import '../services/xiaozhi_service.dart';
import '../utils/audio_util.dart';
import '../utils/voice_activity_detector.dart';
import 'face_view.dart';
import 'visbot_face_view.dart';

class RobotFacePreview extends StatefulWidget {
  final String style;
  const RobotFacePreview({super.key, required this.style});
  @override
  State<RobotFacePreview> createState() => _RobotFacePreviewState();
}

class _RobotFacePreviewState extends State<RobotFacePreview> {
  final _voice = ValueNotifier(XiaozhiVoiceState.listening);
  final _emotion = ValueNotifier('neutral');
  final _speaking = ValueNotifier(false);
  final _level = ValueNotifier(0.0);
  late final FaceController _face;
  Timer? _timer;
  int _frame = 0;
  @override
  void initState() {
    super.initState();
    _face = FaceController(
      voiceStateListenable: _voice,
      emotionListenable: _emotion,
      playbackActiveListenable: _speaking,
    );
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _level.value =
          _speaking.value ? [0.0, .3, .8, .5, .2, 0.0][_frame++ % 6] : 0;
    });
  }

  void _select(XiaozhiVoiceState state) {
    _voice.value = state;
    _speaking.value = state == XiaozhiVoiceState.speaking;
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _face.dispose();
    _voice.dispose();
    _emotion.dispose();
    _speaking.dispose();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Xem thử khuôn mặt')),
    body: Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child:
                widget.style == 'visbot'
                    ? VisbotFaceView(controller: _face, mouthLevel: _level)
                    : FaceView(controller: _face),
          ),
        ),
        const Text('Chỉ mô phỏng hình, không phát tiếng hay chạy động cơ.'),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () => _select(XiaozhiVoiceState.listening),
              child: const Text('Nghe'),
            ),
            TextButton(
              onPressed: () => _select(XiaozhiVoiceState.thinking),
              child: const Text('Suy nghĩ'),
            ),
            TextButton(
              onPressed: () => _select(XiaozhiVoiceState.speaking),
              child: const Text('Nói'),
            ),
          ],
        ),
      ],
    ),
  );
}

class RobotMicrophonePreview extends StatefulWidget {
  const RobotMicrophonePreview({super.key});
  @override
  State<RobotMicrophonePreview> createState() => _RobotMicrophonePreviewState();
}

class _RobotMicrophonePreviewState extends State<RobotMicrophonePreview> {
  StreamSubscription<VoiceFrame>? _frames;
  bool _ownsRecorder = false;
  String? _error;
  double _db = 0;
  bool _speech = false;
  late final VoiceActivityDetector _vad;
  @override
  void initState() {
    super.initState();
    final p = RobotPreferences.instance;
    _vad = VoiceActivityDetector(
      minSpeechDb: p.sensitivity.minSpeechDb,
      speechMarginDb: p.sensitivity.marginDb,
      endFrames: (p.silenceMs / 60).ceil(),
    );
    _start();
  }

  Future<void> _start() async {
    if (AudioUtil.isRecording) {
      setState(
        () => _error = 'Mic đang được sử dụng. Hãy đóng cuộc gọi rồi thử lại.',
      );
      return;
    }
    try {
      _ownsRecorder = true;
      await AudioUtil.startRecording();
      if (!mounted) {
        await AudioUtil.stopRecording();
        return;
      }
      _frames = AudioUtil.frameStream.listen((frame) {
        _vad.process(frame.db, voicing: frame.voicing);
        if (mounted) {
          setState(() {
            _db = frame.db;
            _speech = _vad.inSpeech;
          });
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Không mở được mic: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_frames?.cancel());
    if (_ownsRecorder) unawaited(AudioUtil.stopRecording());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thử độ nhạy mic')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Nói một câu rồi im lặng. Âm thanh thử không gửi lên máy chủ.',
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Text(_error!)
        else ...[
          Text(
            _speech ? 'Đang nhận giọng nói' : 'Đang chờ bạn nói',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: (_db / 90).clamp(0, 1)),
          Text('Âm lượng: ${_db.toStringAsFixed(0)} dB'),
          Text('Ngưỡng phát hiện: ${_vad.thresholdDb.toStringAsFixed(0)} dB'),
        ],
      ],
    ),
  );
}
