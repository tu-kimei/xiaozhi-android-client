import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/services/robot_preferences.dart';
import 'package:ai_assistant/services/standby/call_standby_controller.dart';
import 'package:ai_assistant/services/standby/local_wake_word.dart';
import 'package:ai_assistant/services/standby/screen_power.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/utils/audio_util.dart';

class FakeStandbyScreen implements StandbyScreen {
  bool permission = true;
  final events = <String>[];
  @override
  Future<bool> canSleep() async => permission;
  @override
  Future<void> startLocalListening(String phrase) async {
    events.add('local:$phrase');
  }

  @override
  Future<void> stopLocalListening() async {
    events.add('stop-local');
  }

  @override
  Future<void> sleep() async {
    events.add('sleep');
  }

  @override
  Future<void> wake() async {
    events.add('wake');
  }
}

class FakeKeyword implements WakeWordDetector {
  @override
  void Function()? onDetected;
  @override
  void Function(Object)? onError;
  int accepted = 0, prepared = 0, disposed = 0;
  Completer<void>? preparing;
  @override
  Future<void> prepare(String phrase, double threshold) async {
    prepared++;
    await preparing?.future;
  }

  @override
  void accept(Uint8List pcm) {
    accepted++;
  }

  @override
  void reset() {}
  @override
  Future<void> dispose() async {
    disposed++;
  }
}

class StandbyRig {
  final RobotPreferences preferences;
  final voice = ValueNotifier(XiaozhiVoiceState.waiting),
      playing = ValueNotifier(false);
  final frames = StreamController<VoiceFrame>.broadcast();
  final screen = FakeStandbyScreen(), keyword = FakeKeyword();
  final sessions = <bool>[];
  late final CallStandbyController controller;
  Timer? heartbeat;
  StandbyRig(this.preferences, WidgetTester tester, {bool mic = true}) {
    controller = CallStandbyController(
      preferences: preferences,
      voice: voice,
      playback: playing,
      frames: frames.stream,
      screen: screen,
      detector: keyword,
      now: tester.binding.clock.now,
      setStandby: (sleeping) async {
        sessions.add(sleeping);
      },
    );
    if (mic) {
      heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
        frames.add(VoiceFrame(Uint8List(0), 30, 0, pcm: Uint8List(1920)));
      });
    }
  }
  static Future<StandbyRig> create(
    WidgetTester tester, {
    bool mic = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final p = RobotPreferences();
    await p.load();
    return StandbyRig(p, tester, mic: mic);
  }

  void dispose() {
    heartbeat?.cancel();
    controller.dispose();
    unawaited(frames.close());
    voice.dispose();
    playing.dispose();
  }
}

Future<void> tick(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
}

void main() {
  testWidgets(
    'server sleep interrupts an active reply even with auto sleep off',
    (tester) async {
      final rig = await StandbyRig.create(tester);
      rig.preferences.autoSleep = false;
      rig.voice.value = XiaozhiVoiceState.speaking;
      rig.playing.value = true;
      await tick(tester, 1);
      await rig.controller.requestSleep();
      expect(rig.controller.sleeping, isTrue);
      expect(rig.sessions, [true]);
      expect(rig.screen.events, ['local:Hey Doradino', 'sleep']);
      rig.keyword.onDetected!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(rig.sessions, [true, false]);
      rig.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'server sleep reports permission and missing microphone failures',
    (tester) async {
      final rig = await StandbyRig.create(tester, mic: false);
      rig.screen.permission = false;
      await expectLater(rig.controller.requestSleep(), throwsStateError);
      rig.screen.permission = true;
      await expectLater(rig.controller.requestSleep(), throwsStateError);
      expect(rig.sessions, isEmpty);
      expect(rig.controller.sleeping, isFalse);
      rig.dispose();
      await tester.pump();
    },
  );
  testWidgets('server sleep cannot lock a different foreground app', (
    tester,
  ) async {
    final rig = await StandbyRig.create(tester);
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await expectLater(rig.controller.requestSleep(), throwsStateError);
    expect(rig.screen.events, isEmpty);
    rig.dispose();
    await tester.pump();
  });

  testWidgets('default five minutes, local-only standby and keyword wake', (
    tester,
  ) async {
    final rig = await StandbyRig.create(tester);
    expect(rig.preferences.sleepSeconds, 300);
    await tick(tester, 299);
    expect(rig.controller.sleeping, isFalse);
    await tick(tester, 1);
    expect(rig.controller.sleeping, isTrue);
    expect(rig.sessions, [true]);
    expect(rig.screen.events, ['local:Hey Doradino', 'sleep']);
    await tick(tester, 2);
    expect(rig.keyword.accepted, greaterThan(0));
    rig.keyword.onDetected!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(rig.controller.sleeping, isFalse);
    expect(rig.sessions, [true, false]);
    expect(rig.screen.events, contains('wake'));
    rig.dispose();
    await tester.pump();
  });
  testWidgets('touch and ongoing speech postpone sleep', (tester) async {
    final rig = await StandbyRig.create(tester);
    await tick(tester, 200);
    rig.controller.activity();
    await tick(tester, 200);
    expect(rig.controller.sleeping, isFalse);
    rig.voice.value = XiaozhiVoiceState.speaking;
    rig.playing.value = true;
    await tick(tester, 301);
    expect(rig.controller.sleeping, isFalse);
    rig.playing.value = false;
    rig.voice.value = XiaozhiVoiceState.waiting;
    await tick(tester, 299);
    expect(rig.controller.sleeping, isFalse);
    rig.dispose();
    await tester.pump();
  });
  testWidgets('new activity during model preparation cancels stale sleep', (
    tester,
  ) async {
    final rig = await StandbyRig.create(tester);
    rig.keyword.preparing = Completer<void>();
    await tick(tester, 300);
    expect(rig.controller.transitioning, isTrue);
    rig.controller.activity();
    rig.keyword.preparing!.complete();
    await tester.pump();
    expect(rig.controller.sleeping, isFalse);
    expect(rig.sessions, isEmpty);
    rig.dispose();
    await tester.pump();
  });
  testWidgets(
    'missing permission or mic never locks the screen or changes the active session',
    (tester) async {
      final rig = await StandbyRig.create(tester, mic: false);
      rig.screen.permission = false;
      await rig.controller.sleep(manual: true);
      expect(rig.screen.events, isEmpty);
      expect(rig.sessions, isEmpty);
      rig.screen.permission = true;
      await rig.controller.sleep(manual: true);
      expect(rig.controller.error, contains('Mic'));
      expect(rig.sessions, isEmpty);
      rig.dispose();
      await tester.pump();
    },
  );
  testWidgets('physical resume wakes once and does not poison the next sleep', (
    tester,
  ) async {
    final rig = await StandbyRig.create(tester);
    await tick(tester, 300);
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(rig.controller.sleeping, isFalse);
    await tick(tester, 300);
    expect(rig.controller.sleeping, isTrue);
    expect(rig.screen.events.where((e) => e == 'wake').length, 1);
    rig.dispose();
    await tester.pump();
  });
  testWidgets('background activity does not auto-lock another foreground app', (
    tester,
  ) async {
    final rig = await StandbyRig.create(tester);
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tick(tester, 400);
    expect(rig.screen.events, isEmpty);
    rig.dispose();
    await tester.pump();
  });
  testWidgets(
    'microphone interruption wakes the screen instead of stranding the user',
    (tester) async {
      final rig = await StandbyRig.create(tester);
      await tick(tester, 300);
      expect(rig.controller.sleeping, isTrue);
      rig.heartbeat!.cancel();
      await tick(tester, 9);
      expect(rig.controller.sleeping, isFalse);
      expect(rig.controller.error, contains('Mic'));
      rig.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'keyword disabled sleeps without local CPU service and resumes physically',
    (tester) async {
      final rig = await StandbyRig.create(tester, mic: false);
      rig.preferences.wakeWordEnabled = false;
      await tick(tester, 300);
      expect(rig.controller.sleeping, isTrue);
      expect(rig.keyword.prepared, 0);
      expect(rig.screen.events, ['sleep']);
      rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(rig.controller.sleeping, isFalse);
      expect(rig.sessions, [true, false]);
      rig.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'closing the call during preparation never locks another screen',
    (tester) async {
      final rig = await StandbyRig.create(tester);
      rig.keyword.preparing = Completer<void>();
      await tick(tester, 300);
      rig.dispose();
      rig.keyword.preparing!.complete();
      await tester.pump();
      expect(rig.screen.events, contains('stop-local'));
      expect(rig.screen.events, isNot(contains('sleep')));
      expect(rig.keyword.disposed, 1);
    },
  );
  testWidgets(
    'leaving the foreground while models prepare never locks another app',
    (tester) async {
      final rig = await StandbyRig.create(tester);
      rig.keyword.preparing = Completer<void>();
      await tick(tester, 300);
      expect(rig.controller.transitioning, isTrue);
      rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      rig.keyword.preparing!.complete();
      await tester.pump();
      expect(rig.screen.events, isNot(contains('sleep')));
      expect(rig.sessions, isEmpty);
      rig.dispose();
      await tester.pump();
    },
  );
}
