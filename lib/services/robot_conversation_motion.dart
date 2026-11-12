import 'dart:async';
import 'dart:math' as math;
import 'face_controller.dart';
import 'natural_gesture_policy.dart';
import 'robot_motion_controller.dart';
import 'robot_preferences.dart';
import 'xiaozhi_service.dart' show XiaozhiVoiceState;

/// A rare joyful forward/back pair, never a movement after every reply.
class RobotConversationMotion {
  final FaceController face;
  final RobotMotionController motion;
  final RobotPreferences preferences;
  final double Function() random;
  final DateTime Function() now;
  Timer? _pending;
  DateTime? _joyUntil;
  DateTime? _lastMove;
  bool _joySeen = false;
  bool _running = false;
  bool _disposed = false;

  RobotConversationMotion({
    required this.face,
    required this.motion,
    required this.preferences,
    double Function()? random,
    DateTime Function()? now,
  }) : random = random ?? math.Random().nextDouble,
       now = now ?? DateTime.now {
    face.addListener(_changed);
    preferences.addListener(_changed);
  }

  bool get _enabled =>
      preferences.moveWhenConversing &&
      preferences.voiceEnabled &&
      preferences.wheelsEnabled &&
      preferences.gestures != GestureIntensity.off;
  bool get _safeGap =>
      _enabled &&
      !face.isSpeaking &&
      face.voiceStateListenable.value == XiaozhiVoiceState.waiting;
  bool get _rested =>
      _lastMove == null ||
      now().difference(_lastMove!) >=
          NaturalGesturePolicy.wheelRest(preferences.gestures);

  void _changed() {
    if (_disposed) return;
    if (!_enabled ||
        face.isListening ||
        face.voiceStateListenable.value == XiaozhiVoiceState.idle) {
      _joyUntil = null;
      _pending?.cancel();
      _pending = null;
      if (_running) unawaited(motion.interruptAutomatic());
      return;
    }
    if (face.isSpeaking) {
      _pending?.cancel();
      _pending = null;
      if (_running) unawaited(motion.interruptAutomatic());
      final joyful = NaturalGesturePolicy.isJoyful(face.visbotEmotion);
      if (joyful && !_joySeen) {
        _joySeen = true;
        if (_rested &&
            random() <
                (preferences.gestures == GestureIntensity.lively ? .6 : .35)) {
          _joyUntil = now().add(const Duration(seconds: 8));
        }
      } else if (!joyful) {
        _joySeen = false;
        _joyUntil = null;
      }
      return;
    }
    if (!_safeGap) {
      if (_running) unawaited(motion.interruptAutomatic());
      return; // Buffer gaps still have voiceState=speaking.
    }
    _joySeen = false;
    if (_joyUntil == null || !now().isBefore(_joyUntil!) || !_rested) {
      _joyUntil = null;
      return;
    }
    _pending ??= Timer(const Duration(milliseconds: 600), () {
      _pending = null;
      final valid = _joyUntil != null && now().isBefore(_joyUntil!);
      _joyUntil = null;
      if (_disposed || !valid || !_safeGap || !_rested || motion.busy) return;
      _lastMove = now();
      _running = true;
      unawaited(
        motion
            .celebrate(stillAllowed: () => !_disposed && _safeGap)
            .catchError((Object _) => 'Đã bỏ qua tiến lùi biểu cảm.')
            .whenComplete(() => _running = false),
      );
    });
  }

  void dispose() {
    _disposed = true;
    _pending?.cancel();
    face.removeListener(_changed);
    preferences.removeListener(_changed);
    if (_running) unawaited(motion.interruptAutomatic());
  }
}
