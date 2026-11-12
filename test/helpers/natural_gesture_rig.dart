import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/services/face_controller.dart';
import 'package:ai_assistant/services/robot_motion_controller.dart';
import 'package:ai_assistant/services/robot_preferences.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';

class NaturalHardware implements RobotHardware, AdjustableHeadHardware {
  final angles = <double>[];
  final speeds = <double>[];
  final moves = <String>[];
  int stops = 0;
  Completer<void>? hold;
  @override
  Future<bool> available() async => true;
  @override
  Future<void> head(double angle) async {
    angles.add(angle);
  }

  @override
  Future<void> headAtSpeed(double angle, double speed) async {
    angles.add(angle);
    speeds.add(speed);
  }

  @override
  Future<void> move({
    required double speed,
    required double turnSpeed,
    required int durationMs,
  }) {
    moves.add('$speed:$durationMs');
    return hold?.future ?? Future.value();
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

class NaturalRig {
  final RobotPreferences preferences;
  final hardware = NaturalHardware();
  final voice = ValueNotifier(XiaozhiVoiceState.waiting);
  final emotion = ValueNotifier('neutral');
  final playing = ValueNotifier(false);
  final text = ValueNotifier('');
  late final FaceController face;
  late final RobotMotionController motion;
  NaturalRig(this.preferences) {
    face = FaceController(
      voiceStateListenable: voice,
      emotionListenable: emotion,
      playbackActiveListenable: playing,
    );
    motion = RobotMotionController(
      preferences: preferences,
      hardware: hardware,
    );
  }
  static Future<NaturalRig> create({
    bool head = true,
    GestureIntensity profile = GestureIntensity.gentle,
  }) async {
    SharedPreferences.setMockInitialValues({
      'robot_voice': true,
      'robot_wheels': true,
      'robot_sway': head,
      'robot_auto_move': true,
      'robot_gestures': profile.index,
    });
    final preferences = RobotPreferences();
    await preferences.load();
    return NaturalRig(preferences);
  }

  void speak({String mood = 'neutral', String words = ''}) {
    emotion.value = mood;
    text.value = words;
    voice.value = XiaozhiVoiceState.speaking;
    playing.value = true;
  }

  void finish() {
    playing.value = false;
    emotion.value = 'neutral';
    voice.value = XiaozhiVoiceState.waiting;
  }

  void dispose() {
    face.dispose();
    motion.dispose();
    voice.dispose();
    emotion.dispose();
    playing.dispose();
    text.dispose();
    if (hardware.hold != null && !hardware.hold!.isCompleted) {
      hardware.hold!.complete();
    }
  }
}

Future<void> advanceNatural(WidgetTester tester, int ms) async {
  for (var elapsed = 0; elapsed < ms; elapsed += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
