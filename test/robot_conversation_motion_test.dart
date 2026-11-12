import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/robot_conversation_motion.dart';
import 'package:ai_assistant/services/robot_gestures.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'helpers/natural_gesture_rig.dart';

void main() {
  testWidgets(
    'no movement after neutral replies; joy gets a slow forward-back pair',
    (tester) async {
      final rig = await NaturalRig.create(head: false);
      final head = RobotGestures(
        face: rig.face,
        motion: rig.motion,
        preferences: rig.preferences,
        random: () => 0,
      );
      final auto = RobotConversationMotion(
        face: rig.face,
        motion: rig.motion,
        preferences: rig.preferences,
        random: () => 0,
        now: tester.binding.clock.now,
      );
      rig.speak();
      rig.finish();
      await advanceNatural(tester, 2000);
      expect(rig.hardware.moves, isEmpty);
      rig.speak(mood: 'happy');
      await advanceNatural(tester, 1000);
      expect(rig.hardware.moves, isEmpty); // Never while audio is audible.
      rig.finish();
      await advanceNatural(tester, 1600);
      expect(rig.hardware.moves, ['2.0:450', '-2.0:450']);
      rig.speak(mood: 'laughing');
      rig.finish();
      await advanceNatural(tester, 1500);
      expect(rig.hardware.moves.length, 2); // 45-second rest.
      head.dispose();
      auto.dispose();
      rig.dispose();
      await tester.pump();
    },
  );
  testWidgets('child speech drops pending joy instead of saving it for later', (
    tester,
  ) async {
    final rig = await NaturalRig.create();
    final auto = RobotConversationMotion(
      face: rig.face,
      motion: rig.motion,
      preferences: rig.preferences,
      random: () => 0,
      now: tester.binding.clock.now,
    );
    rig.speak(mood: 'happy');
    rig.finish();
    await advanceNatural(tester, 200);
    rig.voice.value = XiaozhiVoiceState.listening;
    await advanceNatural(tester, 1000);
    rig.voice.value = XiaozhiVoiceState.waiting;
    await advanceNatural(tester, 1000);
    expect(rig.hardware.moves, isEmpty);
    auto.dispose();
    rig.dispose();
    await tester.pump();
  });
  testWidgets('interrupting forward prevents the backward half from running', (
    tester,
  ) async {
    final rig = await NaturalRig.create();
    rig.hardware.hold = Completer<void>();
    final auto = RobotConversationMotion(
      face: rig.face,
      motion: rig.motion,
      preferences: rig.preferences,
      random: () => 0,
      now: tester.binding.clock.now,
    );
    rig.speak(mood: 'happy');
    rig.finish();
    await advanceNatural(tester, 700);
    expect(rig.hardware.moves, ['2.0:450']);
    rig.voice.value = XiaozhiVoiceState.listening;
    await advanceNatural(tester, 1500);
    expect(rig.hardware.moves.length, 1);
    expect(rig.hardware.stops, greaterThan(0));
    auto.dispose();
    rig.dispose();
    await tester.pump();
  });
  testWidgets('expired, disabled or unselected joy cannot move wheels', (
    tester,
  ) async {
    final rig = await NaturalRig.create();
    final auto = RobotConversationMotion(
      face: rig.face,
      motion: rig.motion,
      preferences: rig.preferences,
      random: () => 0,
      now: tester.binding.clock.now,
    );
    rig.speak(mood: 'happy');
    await tester.pump(const Duration(seconds: 9));
    rig.finish();
    await advanceNatural(tester, 1000);
    expect(rig.hardware.moves, isEmpty);
    rig.preferences.wheelsEnabled = false;
    rig.speak(mood: 'happy');
    rig.finish();
    await advanceNatural(tester, 1000);
    expect(rig.hardware.moves, isEmpty);
    auto.dispose();
    rig.dispose();
    await tester.pump();
  });
}
