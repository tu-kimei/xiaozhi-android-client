import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'face_controller.dart';
import 'natural_gesture_policy.dart';
import 'robot_motion_controller.dart';
import 'robot_preferences.dart';
import 'xiaozhi_service.dart' show XiaozhiVoiceState;

/// Context cues, never a metronome tied to every TTS sentence.
class RobotGestures {
  final FaceController face;
  final RobotMotionController motion;
  final RobotPreferences preferences;
  final ValueListenable<String>? replyText;
  final double Function() random;
  final DateTime Function() now;
  Timer? _pending;
  DateTime? _lastGesture;
  String _mode = '';
  bool _turnHandled = false;
  bool _thinkingHandled = false;
  bool _disposed = false;
  bool _running = false;

  RobotGestures({
    required this.face,
    required this.motion,
    required this.preferences,
    this.replyText,
    double Function()? random,
    DateTime Function()? now,
  }) : random = random ?? math.Random().nextDouble,
       now = now ?? DateTime.now {
    face.addListener(_changed);
    preferences.addListener(_changed);
    replyText?.addListener(_changed);
    _changed();
  }

  bool get _enabled =>
      preferences.swayWhenSpeaking &&
      preferences.gestures != GestureIntensity.off;
  bool get _rested =>
      _lastGesture == null ||
      now().difference(_lastGesture!) >=
          NaturalGesturePolicy.headRest(preferences.gestures);

  void _schedule(
    NaturalGesture cue,
    bool Function() stillRelevant,
    Duration delay, {
    double? chance,
  }) {
    if (!_enabled ||
        motion.busy ||
        !_rested ||
        _pending != null ||
        random() >=
            (chance ??
                NaturalGesturePolicy.chance(cue, preferences.gestures))) {
      return;
    }
    _pending = Timer(delay, () {
      _pending = null;
      if (_disposed ||
          !_enabled ||
          !_rested ||
          !stillRelevant() ||
          motion.busy) {
        return;
      }
      _lastGesture = now();
      _running = true;
      unawaited(
        motion
            .naturalGesture(cue)
            .catchError((Object _) => 'Đã bỏ qua cử chỉ.')
            .whenComplete(() => _running = false),
      );
    });
  }

  void _changed() {
    if (_disposed) return;
    final mode = '${face.isListening}:${face.isThinking}:${face.isSpeaking}';
    final entered = mode != _mode;
    if (entered) {
      _pending?.cancel();
      _pending = null;
      _mode = mode;
    }
    if (!_enabled) {
      _pending?.cancel();
      _pending = null;
      if (_running) unawaited(motion.interruptAutomatic());
      return;
    }
    final turnActive =
        face.isSpeaking ||
        face.voiceStateListenable.value == XiaozhiVoiceState.speaking;
    if (!turnActive) _turnHandled = false;
    if (!face.isThinking && !turnActive) _thinkingHandled = false;
    if (face.isListening && entered) {
      unawaited(motion.interruptAutomatic());
      _schedule(
        NaturalGesture.acknowledge,
        () => face.isListening,
        const Duration(milliseconds: 1600),
        chance: preferences.gestures == GestureIntensity.lively ? .3 : .15,
      );
    } else if (face.isThinking &&
        face.voiceStateListenable.value == XiaozhiVoiceState.thinking &&
        !_thinkingHandled) {
      _thinkingHandled = true;
      _schedule(
        NaturalGesture.thinking,
        () => face.isThinking,
        const Duration(milliseconds: 650),
      );
    } else if (face.isSpeaking && !_turnHandled) {
      final cue = NaturalGesturePolicy.speakingCue(
        face.visbotEmotion,
        replyText?.value ?? '',
      );
      if (cue == null) return; // Neutral explanation stays still.
      _turnHandled = true;
      _schedule(
        cue,
        () =>
            face.isSpeaking &&
            NaturalGesturePolicy.speakingCue(
                  face.visbotEmotion,
                  replyText?.value ?? '',
                ) ==
                cue,
        const Duration(milliseconds: 350),
      );
    }
  }

  void dispose() {
    _disposed = true;
    _pending?.cancel();
    face.removeListener(_changed);
    preferences.removeListener(_changed);
    replyText?.removeListener(_changed);
    if (_running) unawaited(motion.interruptAutomatic());
  }
}
