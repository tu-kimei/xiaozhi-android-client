import 'package:flutter/foundation.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';

/// 机器人面部情绪枚举。
///
/// 覆盖 Xiaozhi 官方 21 种标准 emotion，并映射到 7 种主要面部神态。
enum RobotFaceEmotion {
  neutral,
  happy,
  sad,
  angry,
  surprised,
  thinking,
  sleepy,
}

/// 面部神态控制层。
///
/// 结合当前会话状态（XiaozhiVoiceState）与服务器下发的情感（emotion），
/// 计算出最终应该呈现的面部表情、嘴型状态以及口部动画周期。
class FaceController extends ChangeNotifier {
  final ValueListenable<XiaozhiVoiceState> voiceStateListenable;
  final ValueListenable<String> emotionListenable;
  final ValueListenable<bool> playbackActiveListenable;

  RobotFaceEmotion _currentEmotion = RobotFaceEmotion.neutral;
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _isThinking = false;

  FaceController({
    required this.voiceStateListenable,
    required this.emotionListenable,
    required this.playbackActiveListenable,
  }) {
    voiceStateListenable.addListener(_onStateChanged);
    emotionListenable.addListener(_onStateChanged);
    playbackActiveListenable.addListener(_onStateChanged);
    _recompute();
  }

  RobotFaceEmotion get currentEmotion => _currentEmotion;
  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;
  bool get isThinking => _isThinking;

  void _onStateChanged() {
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    final vState = voiceStateListenable.value;
    final rawEmotion = emotionListenable.value.toLowerCase().trim();

    _isSpeaking = playbackActiveListenable.value;
    _isListening = !_isSpeaking && vState == XiaozhiVoiceState.listening;
    // A TTS start announces incoming audio; it can still be buffering.
    _isThinking =
        !_isSpeaking &&
        (vState == XiaozhiVoiceState.thinking ||
            vState == XiaozhiVoiceState.speaking);

    if (_isThinking) {
      _currentEmotion = RobotFaceEmotion.thinking;
      return;
    }

    if (_isListening) {
      // Calm attentive eyes; FacePainter adds a small closed-mouth smile.
      _currentEmotion = RobotFaceEmotion.neutral;
      return;
    }

    _currentEmotion = mapEmotion(rawEmotion);
  }

  /// 将服务器 emotion 字符串映射为内置表情
  static RobotFaceEmotion mapEmotion(String emotion) {
    switch (emotion) {
      case 'happy':
      case 'laughing':
      case 'funny':
      case 'loving':
      case 'kissy':
      case 'confident':
      case 'relaxed':
      case 'delicious':
      case 'cool':
      case 'winking':
        return RobotFaceEmotion.happy;

      case 'sad':
      case 'crying':
      case 'disappointed':
      case 'frustrated':
      case 'embarrassed':
        return RobotFaceEmotion.sad;

      case 'angry':
      case 'mad':
        return RobotFaceEmotion.angry;

      case 'surprised':
      case 'shocked':
      case 'curious':
        return RobotFaceEmotion.surprised;

      case 'thinking':
      case 'confused':
      case 'doubt':
        return RobotFaceEmotion.thinking;

      case 'sleepy':
      case 'fatigue':
        return RobotFaceEmotion.sleepy;

      case 'neutral':
      default:
        return RobotFaceEmotion.neutral;
    }
  }

  @override
  void dispose() {
    voiceStateListenable.removeListener(_onStateChanged);
    emotionListenable.removeListener(_onStateChanged);
    playbackActiveListenable.removeListener(_onStateChanged);
    super.dispose();
  }
}
