import 'dart:async';
import 'package:flutter/widgets.dart';
import 'robot_preferences.dart';
import 'robot_service.dart';
import 'natural_gesture_policy.dart';

/// Injectable hardware boundary keeps limits/queue/cancellation testable.
abstract class RobotHardware {
  Future<bool> available();
  Future<void> head(double angle);
  Future<void> move({
    required double speed,
    required double turnSpeed,
    required int durationMs,
  });
  Future<void> stop();
}

abstract interface class AdjustableHeadHardware {
  Future<void> headAtSpeed(double angle, double speed);
}

abstract interface class SeriesRobotHardware {
  Future<void> motionSeries(String kind, List<Map<String, num>> poses);
}

class VisbotHardware
    implements RobotHardware, AdjustableHeadHardware, SeriesRobotHardware {
  @override
  Future<void> motionSeries(String kind, List<Map<String, num>> poses) async =>
      _check(await RobotService.motionSeries(kind, poses));

  @override
  Future<bool> available() => RobotService.isAvailable();
  void _check(Map<dynamic, dynamic>? result) {
    if (result == null || result['result'] != 'success') {
      throw StateError(
        'Robot chưa thực hiện được động tác: ${result?['message'] ?? 'không có phản hồi'}',
      );
    }
  }

  @override
  Future<void> head(double angle) =>
      headAtSpeed(angle, RobotPreferences.instance.headSpeed.toDouble());
  @override
  Future<void> headAtSpeed(double angle, double speed) async =>
      _check(await RobotService.head(angle, speed: speed));
  @override
  Future<void> move({
    required double speed,
    required double turnSpeed,
    required int durationMs,
  }) async => _check(
    await RobotService.move(
      speed: speed,
      turnSpeed: turnSpeed,
      durationMs: durationMs,
    ),
  );
  @override
  Future<void> stop() => RobotService.stop();
}

class RobotMotionController with WidgetsBindingObserver {
  static final instance = RobotMotionController(
    preferences: RobotPreferences.instance,
    hardware: VisbotHardware(),
  );
  final RobotPreferences preferences;
  final RobotHardware hardware;
  final ValueNotifier<bool> moving = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  Future<void> _tail = Future.value();
  Future<void> _stopTail = Future.value();
  Completer<void> _cancel = Completer<void>();
  int _generation = 0;
  int _pending = 0;
  bool _busy = false;
  bool _automaticActive = false;
  int _automaticPending = 0;
  double _headAngle = 0;
  bool get automaticBusy => _automaticActive || _automaticPending > 0;

  Future<void> interruptAutomatic() => automaticBusy ? stop() : Future.value();
  bool _foreground = true;
  bool _stopConfirmed = true;
  DateTime? _automaticRestUntil;
  bool get busy => _busy || _pending > 0;
  DateTime? _lastWheelEnd;
  DateTime? _restUntil;
  int _continuousWheelMs = 0;

  RobotMotionController({required this.preferences, required this.hardware}) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    preferences.addListener(_settingsChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(stop());
  }

  void _settingsChanged() {
    // Any policy/calibration change invalidates already queued commands.
    unawaited(stop());
  }

  Future<void> stop({bool requireConfirmation = false}) {
    _automaticRestUntil = DateTime.now().add(const Duration(seconds: 10));
    _generation++;
    final generation = _generation;
    if (!_cancel.isCompleted) _cancel.complete();
    _cancel = Completer<void>();
    final wasMoving = moving.value;
    _stopConfirmed = false;
    // Never wait behind the movement queue to stop hardware.
    final future = hardware.stop().timeout(const Duration(seconds: 2));
    _stopTail = future.then<void>(
      (_) {
        if (generation != _generation) return;
        _stopConfirmed = true;
        moving.value = false;
        error.value = null;
      },
      onError: (Object e) {
        if (generation != _generation) return;
        error.value = 'Không dừng được robot: $e';
        moving.value = wasMoving;
      },
    );
    return requireConfirmation ? future : _stopTail;
  }

  Future<String> _enqueue(
    Future<String> Function(int) action, {
    bool automatic = false,
    Duration operationTimeout = const Duration(seconds: 15),
  }) {
    if (!_foreground) {
      return Future.error(
        StateError('Robot đã dừng vì ứng dụng không ở phía trước.'),
      );
    }
    if (automatic &&
        _automaticRestUntil != null &&
        DateTime.now().isBefore(_automaticRestUntil!)) {
      return Future.value('Cử chỉ đang tạm nghỉ sau lệnh dừng.');
    }
    if (!automatic && automaticBusy) unawaited(stop());
    if (automatic && busy) {
      return Future.value('Bỏ qua cử chỉ vì robot đang bận.');
    }
    if (_pending >= 8) {
      return Future.error(StateError('Robot có quá nhiều lệnh đang chờ.'));
    }
    final gen = _generation;
    _pending++;
    if (automatic) _automaticPending++;
    final next = _tail.then((_) async {
      _pending--;
      if (automatic) _automaticPending--;
      await _stopTail;
      if (!_stopConfirmed) {
        throw StateError('Chưa xác nhận được robot đã dừng. Hãy thử DỪNG lại.');
      }
      _checkGeneration(gen);
      _busy = true;
      _automaticActive = automatic;
      try {
        if (!await hardware.available().timeout(const Duration(seconds: 2))) {
          throw StateError('Thiết bị này không có phần cứng Visbot.');
        }
        _checkGeneration(gen);
        return await action(gen).timeout(
          operationTimeout,
          onTimeout: () async {
            await stop();
            throw StateError(
              'Động tác quá ${operationTimeout.inSeconds} giây, đã gửi lệnh dừng.',
            );
          },
        );
      } finally {
        _busy = false;
        _automaticActive = false;
      }
    });
    _tail = next.then<void>(
      (_) {},
      onError: (Object e) {
        error.value = e.toString();
      },
    );
    return next;
  }

  void _checkGeneration(int gen) {
    if (gen != _generation) throw StateError('Động tác đã bị dừng.');
  }

  Future<void> _step(
    Future<void> Function() action,
    int gen, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _checkGeneration(gen);
    final canceled = _cancel.future.then(
      (_) => throw StateError('Động tác đã bị dừng.'),
    );
    try {
      await Future.any<void>([action(), canceled]).timeout(timeout);
      _checkGeneration(gen);
    } on TimeoutException {
      await stop();
      throw StateError('Robot phản hồi quá chậm, đã gửi lệnh dừng.');
    }
  }

  Future<String> head(String action) => _enqueue((gen) async {
    if (!preferences.voiceEnabled) {
      throw StateError('Điều khiển bằng giọng nói đang tắt.');
    }
    return _head(action, gen);
  }, operationTimeout: const Duration(seconds: 30));

  Future<String> _head(String action, int gen) async {
    final angles = switch (action) {
      'up' => <double>[-23],
      'down' => <double>[25],
      'center' => <double>[0],
      'nod' => <double>[
        for (var i = 0; i < preferences.nodCount; i++) ...[
          -preferences.nodAngle.toDouble(),
          preferences.nodAngle.toDouble(),
        ],
        0,
      ],
      _ =>
        throw ArgumentError(
          'Động tác đầu không hợp lệ. Visbot không có trục lắc ngang.',
        ),
    };
    for (final angle in angles) {
      await _step(
        () => hardware.head(angle),
        gen,
        timeout: const Duration(seconds: 6),
      );
      _headAngle = angle;
    }
    return 'Đã thực hiện động tác đầu: $action.';
  }

  Future<String> gesture(List<double> angles, {bool speakingNod = false}) =>
      _enqueue((gen) async {
        if (preferences.gestures == GestureIntensity.off &&
            !(speakingNod && preferences.swayWhenSpeaking)) {
          return 'Cử chỉ đang tắt.';
        }
        for (final angle in angles) {
          if (!angle.isFinite || angle < -23 || angle > 25) {
            throw ArgumentError('Góc đầu không hợp lệ.');
          }
          await _step(
            () => hardware.head(angle),
            gen,
            timeout: const Duration(seconds: 6),
          );
        }
        return 'Đã cử chỉ.';
      }, automatic: true);

  Future<String> move(
    String direction, {
    int steps = 1,
    double rotations = 1,
  }) => _enqueue(
    (gen) => _move(direction, gen, steps: steps, rotations: rotations),
  );

  Future<String> naturalGesture(NaturalGesture kind) => _enqueue((gen) async {
    if (preferences.gestures == GestureIntensity.off ||
        !preferences.swayWhenSpeaking) {
      return 'Cử chỉ đầu đang tắt.';
    }
    final anchor = _headAngle.clamp(-8.0, 8.0);
    if (hardware is SeriesRobotHardware) {
      final beat = (300 * 25 / preferences.headSpeed).round().clamp(250, 650);
      final poses = switch (kind) {
        NaturalGesture.acknowledge => [
          (anchor + 12, beat),
          (anchor, beat + 80),
        ],
        NaturalGesture.joyful => [
          (anchor + 15, beat),
          (anchor, beat),
          (anchor + 10, beat),
          (anchor, beat + 80),
        ],
        NaturalGesture.thinking => [(anchor - 3, beat + 150)],
        NaturalGesture.sad => [(anchor + 3, beat + 150)],
        NaturalGesture.surprised => [(anchor - 4, beat)],
      };
      await _runSeries('head', [
        for (final pose in poses) {'angle': pose.$1, 'durationMs': pose.$2},
      ], gen);
      _headAngle = poses.last.$1;
      return 'Đã thực hiện cử chỉ tự nhiên.';
    }
    final poses = switch (kind) {
      NaturalGesture.acknowledge => [
        (anchor - 3, 8.0, 60),
        (anchor + 5, 12.0, 100),
        (anchor, 7.0, 0),
      ],
      NaturalGesture.joyful => [
        (anchor - 4, 10.0, 80),
        (anchor + 2, 11.0, 80),
        (anchor, 7.0, 0),
      ],
      NaturalGesture.thinking => [(anchor - 3, 6.0, 0)],
      NaturalGesture.sad => [(anchor + 3, 6.0, 0)],
      NaturalGesture.surprised => [(anchor - 4, 9.0, 0)],
    };
    for (final pose in poses) {
      final (angle, baseSpeed, pause) = pose;
      final speed = (baseSpeed * preferences.headSpeed / 25).clamp(4.0, 15.0);
      await _step(
        () =>
            hardware is AdjustableHeadHardware
                ? (hardware as AdjustableHeadHardware).headAtSpeed(angle, speed)
                : hardware.head(angle),
        gen,
        timeout: const Duration(seconds: 6),
      );
      _headAngle = angle;
      if (pause > 0) {
        await _step(
          () => Future<void>.delayed(Duration(milliseconds: pause)),
          gen,
        );
      }
    }
    return 'Đã thực hiện cử chỉ tự nhiên.';
  }, automatic: true);

  Future<String> celebrate({required bool Function() stillAllowed}) =>
      _enqueue((gen) async {
        if (!preferences.moveWhenConversing ||
            preferences.gestures == GestureIntensity.off) {
          return 'Tiến lùi biểu cảm đang tắt.';
        }
        if (hardware is SeriesRobotHardware) {
          _checkGeneration(gen);
          if (!stillAllowed()) return 'Đã bỏ qua cử chỉ vì lượt nói thay đổi.';
          if (!preferences.voiceEnabled || !preferences.wheelsEnabled) {
            throw StateError('Bánh xe đang tắt trong Cài đặt → Robot.');
          }
          final now = DateTime.now();
          if (_restUntil != null && now.isBefore(_restUntil!)) {
            return 'Robot đang nghỉ.';
          }
          if (_lastWheelEnd == null ||
              now.difference(_lastWheelEnd!).inSeconds >= 5) {
            _continuousWheelMs = 0;
          }
          if (_continuousWheelMs + 900 > 30000) {
            _restUntil = now.add(const Duration(seconds: 5));
            return 'Robot đang nghỉ.';
          }
          final speed = preferences.wheelSpeed.clamp(1, 2).toDouble();
          _continuousWheelMs += 900;
          moving.value = true;
          try {
            await _runSeries('wheels', [
              {'speed': speed, 'durationMs': 450},
              {'speed': -speed, 'durationMs': 450},
            ], gen);
          } finally {
            moving.value = false;
            _lastWheelEnd = DateTime.now();
          }
          return 'Đã tiến lùi nhẹ khi vui.';
        }
        for (final direction in ['forward', 'backward']) {
          _checkGeneration(gen);
          if (!stillAllowed()) return 'Đã bỏ qua cử chỉ vì lượt nói thay đổi.';
          await _move(direction, gen, automatic: true);
          if (direction == 'forward') {
            await _step(
              () => Future<void>.delayed(const Duration(milliseconds: 180)),
              gen,
            );
          }
        }
        return 'Đã tiến lùi nhẹ khi vui.';
      }, automatic: true);

  Future<void> _runSeries(
    String kind,
    List<Map<String, num>> poses,
    int gen,
  ) async {
    try {
      await _step(
        () => (hardware as SeriesRobotHardware).motionSeries(kind, poses),
        gen,
        timeout: Duration(
          milliseconds:
              poses.fold<int>(
                0,
                (sum, pose) => sum + pose['durationMs']!.toInt(),
              ) +
              2000,
        ),
      );
    } catch (_) {
      if (gen == _generation) await stop();
      rethrow;
    }
  }

  Future<String> _move(
    String direction,
    int gen, {
    int steps = 1,
    double rotations = 1,
    bool automatic = false,
  }) async {
    if (!preferences.voiceEnabled || !preferences.wheelsEnabled) {
      throw StateError('Bánh xe đang tắt trong Cài đặt → Robot.');
    }
    if (steps < 1 ||
        steps > 10 ||
        !rotations.isFinite ||
        rotations < 0.25 ||
        rotations > 5) {
      throw ArgumentError('Số bước/vòng nằm ngoài giới hạn.');
    }
    final straight = direction == 'forward' || direction == 'backward';
    if (!straight &&
        !['left', 'right', 'spinleft', 'spinright'].contains(direction)) {
      throw ArgumentError('Hướng không hợp lệ.');
    }
    final durationMs =
        automatic
            ? 450
            : straight
            ? steps * preferences.stepMs
            : ((direction == 'left' || direction == 'right'
                        ? 0.25
                        : rotations) *
                    preferences.rotationMs)
                .round();
    if (durationMs <= 0 || durationMs > 10000) {
      throw StateError('Mỗi lệnh di chuyển tối đa 10 giây.');
    }
    final now = DateTime.now();
    if (_restUntil != null && now.isBefore(_restUntil!)) {
      throw StateError('Robot đang nghỉ 5 giây sau khi di chuyển lâu.');
    }
    if (_lastWheelEnd == null ||
        now.difference(_lastWheelEnd!) >= const Duration(seconds: 2)) {
      _continuousWheelMs = 0;
    }
    if (_continuousWheelMs + durationMs > 30000) {
      _restUntil = now.add(const Duration(seconds: 5));
      await stop();
      throw StateError(
        'Đã đạt giới hạn 30 giây liên tục. Robot cần nghỉ 5 giây.',
      );
    }
    _continuousWheelMs += durationMs;
    final speed =
        straight
            ? (direction == 'forward' ? 1 : -1) *
                (automatic
                    ? preferences.wheelSpeed.clamp(1, 2).toDouble()
                    : preferences.wheelSpeed.toDouble())
            : 0.0;
    final turnSpeed =
        straight
            ? 0.0
            : (direction.endsWith('left') ? 1 : -1) *
                preferences.turnSpeed.toDouble();
    moving.value = true;
    try {
      await _step(
        () => hardware.move(
          speed: speed,
          turnSpeed: turnSpeed,
          durationMs: durationMs,
        ),
        gen,
        timeout: Duration(milliseconds: durationMs + 2000),
      );
      return 'Đã $direction trong $durationMs ms.';
    } finally {
      // Also stop on early completion, platform errors, and timeout.
      if (gen == _generation) {
        try {
          await hardware.stop().timeout(const Duration(seconds: 2));
          moving.value = false;
        } catch (_) {
          await stop();
          rethrow;
        }
      }
      _lastWheelEnd = DateTime.now();
      if (_continuousWheelMs >= 30000) {
        _restUntil = _lastWheelEnd!.add(const Duration(seconds: 5));
      }
    }
  }

  static bool isEmergencyStop(String text) => RegExp(
    r'(^|[^\p{L}])(dừng|đứng lại|stop)(?=$|[^\p{L}])',
    caseSensitive: false,
    unicode: true,
  ).hasMatch(text);

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    preferences.removeListener(_settingsChanged);
    unawaited(stop());
  }
}
