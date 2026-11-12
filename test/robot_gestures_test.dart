import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/robot_gestures.dart';
import 'package:ai_assistant/services/robot_preferences.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'helpers/natural_gesture_rig.dart';

void main() {
  testWidgets('neutral speech and buffer gaps never trigger a periodic nod', (
    tester,
  ) async {
    final rig = await NaturalRig.create();
    final gestures = RobotGestures(
      face: rig.face,
      motion: rig.motion,
      preferences: rig.preferences,
      replyText: rig.text,
      random: () => 0,
      now: tester.binding.clock.now,
    );
    for (var i = 0; i < 3; i++) {
      rig.speak();
      await advanceNatural(tester, 2000);
      rig.playing.value = false;
      await advanceNatural(tester, 800); // Audio buffer gap.
      rig.playing.value = true;
      await advanceNatural(tester, 1000);
      rig.finish();
      await advanceNatural(tester, 1000);
    }
    expect(rig.hardware.angles, isEmpty);
    gestures.dispose();
    rig.dispose();
    await tester.pump();
  });
  testWidgets('agreement gets one asymmetric small nod with a 24-second rest', (
    tester,
  ) async {
    final rig = await NaturalRig.create();
    final gestures = RobotGestures(
      face: rig.face,
      motion: rig.motion,
      preferences: rig.preferences,
      replyText: rig.text,
      random: () => 0,
      now: tester.binding.clock.now,
    );
    rig.speak(words: 'Đúng rồi, mình đồng ý.');
    await advanceNatural(tester, 1500);
    expect(rig.hardware.angles, [-3, 5, 0]);
    expect(rig.hardware.speeds, [8, 12, 7]);
    rig.finish();
    rig.speak(words: 'Đúng vậy.');
    await advanceNatural(tester, 1500);
    expect(rig.hardware.angles.length, 3);
    rig.finish();
    await tester.pump(const Duration(seconds: 25));
    rig.speak(words: 'Vâng, được chứ!');
    await advanceNatural(tester, 1500);
    expect(rig.hardware.angles.length, 6);
    gestures.dispose();
    rig.dispose();
    await tester.pump();
  });
  testWidgets(
    'quiet profile and random selection can both leave the robot still',
    (tester) async {
      final rig = await NaturalRig.create(profile: GestureIntensity.off);
      final gestures = RobotGestures(
        face: rig.face,
        motion: rig.motion,
        preferences: rig.preferences,
        replyText: rig.text,
        random: () => 1,
        now: tester.binding.clock.now,
      );
      rig.speak(mood: 'happy');
      await advanceNatural(tester, 2000);
      expect(rig.hardware.angles, isEmpty);
      rig.finish();
      rig.preferences.gestures = GestureIntensity.gentle;
      rig.speak(mood: 'happy');
      await advanceNatural(tester, 2000);
      expect(rig.hardware.angles, isEmpty);
      gestures.dispose();
      rig.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'child speech cancels a running automatic nod but not future explicit commands',
    (tester) async {
      final rig = await NaturalRig.create();
      final gestures = RobotGestures(
        face: rig.face,
        motion: rig.motion,
        preferences: rig.preferences,
        replyText: rig.text,
        random: () => 0,
        now: tester.binding.clock.now,
      );
      rig.speak(words: 'Đúng rồi.');
      await advanceNatural(tester, 400);
      expect(rig.hardware.angles, [-3]);
      rig.playing.value = false;
      rig.voice.value = XiaozhiVoiceState.listening;
      await advanceNatural(tester, 300);
      expect(rig.hardware.angles, [-3]);
      expect(rig.hardware.stops, greaterThan(0));
      await rig.motion.head('up');
      expect(rig.hardware.angles.last, -23);
      gestures.dispose();
      rig.dispose();
      await tester.pump();
    },
  );
}
