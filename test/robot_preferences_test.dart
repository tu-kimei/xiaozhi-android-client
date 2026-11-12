import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/utils/voice_activity_detector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/services/robot_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'migrate existing speed and face choices, persist custom settings, reset safely',
    () async {
      SharedPreferences.setMockInitialValues({
        'robot_medium_speed': true,
        'face_style': 'visbot',
      });
      final p = RobotPreferences();
      await p.load();
      expect(p.wheelSpeed, 15);
      expect(p.turnSpeed, 200);
      expect(p.faceStyle, 'visbot');
      await p.update(
        voice: true,
        wheels: true,
        head: 17,
        speed: 6,
        turn: 80,
        nods: 2,
        amplitude: 12,
        mic: VoiceSensitivity.high,
        silence: 1200,
        sway: true,
        autoMove: true,
      );
      final restored = RobotPreferences();
      await restored.load();
      expect(
        [
          restored.headSpeed,
          restored.wheelSpeed,
          restored.turnSpeed,
          restored.nodCount,
          restored.nodAngle,
          restored.silenceMs,
        ],
        [17, 6, 80, 2, 12, 1200],
      );
      expect(restored.sensitivity, VoiceSensitivity.high);
      expect(restored.moveWhenConversing, isTrue);
      await restored.reset();
      final reset = RobotPreferences();
      await reset.load();
      expect(
        reset.voiceEnabled ||
            reset.wheelsEnabled ||
            reset.swayWhenSpeaking ||
            reset.moveWhenConversing,
        isFalse,
      );
      expect(reset.faceStyle, 'simple');
      expect(reset.wheelSpeed, 10); // Old legacy speed cannot undo reset.
    },
  );
  test(
    'settings clamp corrupt storage and caller values to hardware limits',
    () async {
      SharedPreferences.setMockInitialValues({
        'robot_head_speed': 999,
        'robot_wheel_speed': -2,
        'robot_nod_count': 99,
        'robot_sensitivity': 99,
        'face_style': 'unknown',
      });
      final p = RobotPreferences();
      await p.load();
      expect([p.headSpeed, p.wheelSpeed, p.nodCount], [30, 1, 3]);
      expect(p.faceStyle, 'simple');
      await p.update(
        head: 0,
        speed: 100,
        turn: 999,
        nods: 0,
        amplitude: 99,
        silence: 1,
      );
      expect(
        [
          p.headSpeed,
          p.wheelSpeed,
          p.turnSpeed,
          p.nodCount,
          p.nodAngle,
          p.silenceMs,
        ],
        [10, 15, 200, 1, 20, 300],
      );
    },
  );
  test(
    'high sensitivity detects quiet voiced speech while normal rejects it',
    () {
      bool detects(VoiceSensitivity sensitivity) {
        final vad = VoiceActivityDetector(
          minSpeechDb: sensitivity.minSpeechDb,
          speechMarginDb: sensitivity.marginDb,
        );
        for (var i = 0; i < 8; i++) {
          vad.process(30, voicing: 0);
        }
        for (var i = 0; i < 4; i++) {
          vad.process(48, voicing: .9);
        }
        return vad.inSpeech;
      }

      expect(detects(VoiceSensitivity.high), isTrue);
      expect(detects(VoiceSensitivity.normal), isFalse);
      expect(detects(VoiceSensitivity.low), isFalse);
    },
  );
}
