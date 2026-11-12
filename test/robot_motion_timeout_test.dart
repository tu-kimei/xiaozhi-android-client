import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/services/robot_motion_controller.dart';
import 'package:ai_assistant/services/robot_preferences.dart';

class UnresponsiveRobotHardware implements RobotHardware {
  final pending = Completer<void>();
  int stops = 0;
  @override
  Future<bool> available() async => true;
  @override
  Future<void> head(double angle) async {}
  @override
  Future<void> move({
    required double speed,
    required double turnSpeed,
    required int durationMs,
  }) => pending.future;
  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  testWidgets(
    'watchdog stops unresponsive hardware and releases the movement queue',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'robot_voice': true,
        'robot_wheels': true,
      });
      final preferences = RobotPreferences();
      await preferences.load();
      final hardware = UnresponsiveRobotHardware();
      final motion = RobotMotionController(
        preferences: preferences,
        hardware: hardware,
      );
      final failed = expectLater(motion.move('forward'), throwsStateError);
      await tester.pump();
      expect(motion.moving.value, isTrue);
      await tester.pump(const Duration(seconds: 3));
      await failed;
      expect(hardware.stops, greaterThan(0));
      expect(motion.moving.value, isFalse);
      hardware.pending.complete();
      motion.dispose();
      await tester.pump();
    },
  );
}
