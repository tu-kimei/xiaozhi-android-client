import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/services/robot_motion_controller.dart';
import 'package:ai_assistant/services/robot_preferences.dart';
import 'package:ai_assistant/services/mcp/mcp_server.dart';
import 'package:ai_assistant/services/mcp/robot_tools.dart';

class FakeRobotHardware implements RobotHardware {
  final events = <String>[];
  final moves = <Completer<void>>[];
  bool holdMoves = false;
  bool supported = true;
  bool failStop = false;
  @override
  Future<bool> available() async => supported;
  @override
  Future<void> head(double angle) async {
    events.add('head:$angle');
  }

  @override
  Future<void> move({
    required double speed,
    required double turnSpeed,
    required int durationMs,
  }) {
    events.add('move:$speed:$turnSpeed:$durationMs');
    if (!holdMoves) return Future.value();
    final done = Completer<void>();
    moves.add(done);
    return done.future;
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    if (failStop) throw StateError('hardware stop failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RobotPreferences preferences;
  late FakeRobotHardware hardware;
  late RobotMotionController motion;
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'robot_voice': true,
      'robot_wheels': true,
    });
    preferences = RobotPreferences();
    await preferences.load();
    hardware = FakeRobotHardware();
    motion = RobotMotionController(
      preferences: preferences,
      hardware: hardware,
    );
  });
  tearDown(() {
    motion.dispose();
  });

  test(
    'moves and head commands run in order, normal completion keeps the queue',
    () async {
      hardware.holdMoves = true;
      final first = motion.move('forward');
      final next = motion.head('up');
      await tick();
      expect(hardware.events, ['move:10.0:0.0:500']);
      expect(motion.moving.value, isTrue);
      hardware.moves.single.complete();
      await first;
      await next;
      expect(hardware.events, ['move:10.0:0.0:500', 'stop', 'head:-23.0']);
      expect(motion.moving.value, isFalse);
    },
  );
  test(
    'stop bypasses the queue and invalidates both active and queued work',
    () async {
      hardware.holdMoves = true;
      final first = motion.move('spinleft');
      final next = motion.head('up');
      final firstStopped = expectLater(first, throwsStateError);
      final nextStopped = expectLater(next, throwsStateError);
      await tick();
      await motion.stop();
      await firstStopped;
      await nextStopped;
      expect(hardware.events.where((e) => e.startsWith('head')), isEmpty);
      expect(hardware.events.last, 'stop');
      hardware.moves.single.complete();
      await motion.head('center'); // New explicit commands are still allowed.
      expect(hardware.events.last, 'head:0.0');
    },
  );
  test(
    'limits reject oversized commands and enforce a 30-second continuous budget',
    () async {
      preferences.stepMs = 1000;
      for (var i = 0; i < 3; i++) {
        await motion.move('forward', steps: 10);
      }
      await expectLater(motion.move('forward'), throwsStateError);
      expect(hardware.events.where((e) => e.startsWith('move')).length, 3);
      preferences.rotationMs = 6000;
      await expectLater(
        motion.move('spinleft', rotations: 5),
        throwsStateError,
      );
      await expectLater(motion.move('forward', steps: 11), throwsArgumentError);
      await expectLater(
        motion.move('spinleft', rotations: double.nan),
        throwsArgumentError,
      );
      await expectLater(motion.head('shake'), throwsArgumentError);
    },
  );
  test(
    'policy changes stop current motion; disabled wheels and background cannot run',
    () async {
      hardware.holdMoves = true;
      final active = motion.move('forward');
      final stopped = expectLater(active, throwsStateError);
      await tick();
      await preferences.update(wheels: false);
      await stopped;
      await expectLater(motion.move('forward'), throwsStateError);
      motion.didChangeAppLifecycleState(AppLifecycleState.paused);
      await expectLater(motion.head('up'), throwsStateError);
      hardware.moves.single.complete();
    },
  );
  test(
    'discovery hides disabled actions but emergency stop is always available',
    () async {
      final server = McpServer();
      registerRobotTools(server, motion, preferences, available: () => true);
      Map<String, dynamic> req(
        String method,
        int id, [
        Map<String, dynamic>? params,
      ]) => {
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      };
      await preferences.update(voice: false, wheels: false);
      final listed = await server.handle(req('tools/list', 1));
      expect(listed!['result']['tools'].map((t) => t['name']), [
        'self.robot.stop',
      ]);
      final stop = await server.handle(
        req('tools/call', 2, {'name': 'self.robot.stop'}),
      );
      expect(stop!['result']['isError'], isFalse);
      await preferences.update(voice: true);
      final listedHead = await server.handle(req('tools/list', 3));
      expect(listedHead!['result']['tools'].map((t) => t['name']), [
        'self.robot.stop',
        'self.robot.head',
      ]);
    },
  );
  test(
    'head direction matches Visbot and nod repeats three full cycles',
    () async {
      await motion.head('up');
      await motion.head('down');
      await motion.head('nod');
      expect(hardware.events, [
        'head:-23.0',
        'head:25.0',
        'head:-18.0',
        'head:18.0',
        'head:-18.0',
        'head:18.0',
        'head:-18.0',
        'head:18.0',
        'head:0.0',
      ]);
    },
  );

  test('custom nod shape and wheel speeds reach the hardware', () async {
    await preferences.update(nods: 2, amplitude: 12, speed: 6, turn: 80);
    await motion.head('nod');
    expect(hardware.events, [
      'stop',
      'head:-12.0',
      'head:12.0',
      'head:-12.0',
      'head:12.0',
      'head:0.0',
    ]);
    await motion.move('forward');
    await motion.move('spinleft');
    expect(hardware.events, contains('move:6.0:0.0:500'));
    expect(hardware.events, contains('move:0.0:80.0:1500'));
  });

  test('Vietnamese emergency words match whole words', () {
    for (final text in ['Dừng lại!', 'robot đứng lại', 'STOP', 'dừng robot']) {
      expect(RobotMotionController.isEmergencyStop(text), isTrue, reason: text);
    }
    for (final text in ['tiến lên', 'stopping', 'dừngg', 'đứng thẳng']) {
      expect(
        RobotMotionController.isEmergencyStop(text),
        isFalse,
        reason: text,
      );
    }
  });

  test(
    'failed stop is an MCP error and blocks new commands until confirmed',
    () async {
      hardware.failStop = true;
      final server = McpServer();
      registerRobotTools(server, motion, preferences, available: () => true);
      final result = await server.handle({
        'jsonrpc': '2.0',
        'id': 99,
        'method': 'tools/call',
        'params': {'name': 'self.robot.stop'},
      });
      expect(result!['result']['isError'], isTrue);
      expect(motion.error.value, contains('Không dừng được'));
      await expectLater(motion.head('up'), throwsStateError);
      expect(hardware.events.where((e) => e.startsWith('head')), isEmpty);
      hardware.failStop = false;
      await motion.stop(requireConfirmation: true);
      await motion.head('center');
      expect(hardware.events.last, 'head:0.0');
    },
  );
}
