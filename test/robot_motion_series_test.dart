import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/robot_motion_controller.dart';
import 'package:ai_assistant/services/robot_preferences.dart';
import 'package:ai_assistant/services/natural_gesture_policy.dart';
import 'robot_motion_controller_test.dart' show FakeRobotHardware;

class SeriesHardware extends FakeRobotHardware implements SeriesRobotHardware {
  String? kind;
  List<Map<String, num>> poses = [];
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<void> motionSeries(String kind, List<Map<String, num>> poses) async {
    this.kind = kind;
    this.poses = poses;
    if (fail) throw StateError('motor failure');
    if (pending != null) await pending!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SeriesHardware hardware;
  late RobotMotionController motion;
  setUp(() {
    hardware = SeriesHardware();
    final prefs =
        RobotPreferences()
          ..voiceEnabled = true
          ..wheelsEnabled = true
          ..swayWhenSpeaking = true
          ..moveWhenConversing = true;
    motion = RobotMotionController(preferences: prefs, hardware: hardware);
  });
  tearDown(() => motion.dispose());

  test('acknowledgement is one native nod down and back', () async {
    await motion.naturalGesture(NaturalGesture.acknowledge);
    expect(hardware.kind, 'head');
    expect(hardware.poses.map((p) => p['angle']), [12, 0]);
    expect(hardware.events, isEmpty);
  });
  test('wheel pair runs as one native series without extra cancel', () async {
    await motion.celebrate(stillAllowed: () => true);
    expect(hardware.kind, 'wheels');
    expect(hardware.poses.map((p) => p['speed']), [2, -2]);
    expect(
      hardware.poses.fold<int>(0, (n, p) => n + p['durationMs']!.toInt()),
      900,
    );
    expect(hardware.events, isEmpty);
    expect(motion.moving.value, isFalse);
  });
  test('stop interrupts the whole active native series', () async {
    hardware.pending = Completer<void>();
    final active = motion.celebrate(stillAllowed: () => true);
    final failed = expectLater(active, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(motion.moving.value, isTrue);
    await motion.stop();
    await failed;
    expect(hardware.events, ['stop']);
    expect(motion.moving.value, isFalse);
    hardware.pending!.complete();
  });
  test('native series failure sends a hardware stop', () async {
    hardware.fail = true;
    await expectLater(
      motion.celebrate(stillAllowed: () => true),
      throwsStateError,
    );
    expect(hardware.events, ['stop']);
    expect(motion.moving.value, isFalse);
  });
}
