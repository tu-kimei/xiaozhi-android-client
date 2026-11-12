import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../robot_preferences.dart';
import '../xiaozhi_service.dart' show XiaozhiVoiceState;
import '../../utils/audio_util.dart' show VoiceFrame;
import 'local_wake_word.dart';
import 'screen_power.dart';

/// Idle timeout and local wake lifecycle scoped to the open call route.
class CallStandbyController extends ChangeNotifier with WidgetsBindingObserver {
  final RobotPreferences preferences;
  final ValueListenable<XiaozhiVoiceState> voice;
  final ValueListenable<bool> playback;
  final Future<void> Function(bool) setStandby;
  final StandbyScreen screen;
  final WakeWordDetector detector;
  final DateTime Function() now;
  Timer? _idle;
  Timer? _micHealth;
  DateTime? _lastFrame;
  StreamSubscription<VoiceFrame>? _frames;
  bool sleeping = false;
  bool transitioning = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _wakePending = false;
  int _activityGeneration = 0;
  String? error;

  CallStandbyController({
    required this.preferences,
    required this.voice,
    required this.playback,
    required this.setStandby,
    required Stream<VoiceFrame> frames,
    StandbyScreen? screen,
    WakeWordDetector? detector,
    DateTime Function()? now,
  }) : screen = screen ?? AndroidStandbyScreen(),
       detector = detector ?? LocalWakeWord(),
       now = now ?? DateTime.now {
    preferences.addListener(_settingsChanged);
    voice.addListener(_voiceChanged);
    playback.addListener(_voiceChanged);
    WidgetsBinding.instance.addObserver(this);
    this.detector.onDetected = () => unawaited(wake());
    this.detector.onError = (e) {
      error = 'Bộ nghe từ đánh thức: $e';
      if (sleeping) unawaited(wake());
    };
    _frames = frames.listen((frame) {
      _lastFrame = this.now();
      if (sleeping &&
          !transitioning &&
          preferences.wakeWordEnabled &&
          frame.pcm != null) {
        this.detector.accept(frame.pcm!);
      }
    });
    activity();
  }

  bool get _busy =>
      playback.value ||
      [
        XiaozhiVoiceState.listening,
        XiaozhiVoiceState.thinking,
        XiaozhiVoiceState.speaking,
        XiaozhiVoiceState.micBusy,
      ].contains(voice.value);

  void activity() {
    if (_disposed) return;
    _activityGeneration++;
    if (sleeping) {
      unawaited(wake());
      return;
    }
    _arm();
  }

  void _arm() {
    _idle?.cancel();
    if (_disposed ||
        sleeping ||
        transitioning ||
        !preferences.autoSleep ||
        !_foreground) {
      return;
    }
    _idle = Timer(Duration(seconds: preferences.sleepSeconds), () {
      if (_busy) {
        _arm();
        return;
      }
      unawaited(sleep());
    });
  }

  void _voiceChanged() {
    if (!sleeping && !transitioning) activity();
  }

  void _settingsChanged() {
    if (sleeping) {
      unawaited(wake());
    } else {
      activity();
    }
  }

  /// Server requests must report failure rather than acknowledge a dark screen
  /// when permission, microphone readiness or model preparation failed.
  Future<void> requestSleep() async {
    if (_disposed || !_foreground || transitioning) {
      throw StateError('Robot chưa sẵn sàng chuyển sang nghỉ.');
    }
    if (sleeping) return;
    await sleep(manual: true);
    if (!sleeping) throw StateError(error ?? 'Không chuyển sang nghỉ được.');
  }

  Future<void> sleep({bool manual = false}) async {
    if (_disposed ||
        sleeping ||
        transitioning ||
        !_foreground ||
        (!manual && _busy)) {
      return;
    }
    _idle?.cancel();
    transitioning = true;
    error = null;
    notifyListeners();
    final generation = _activityGeneration;
    var suspended = false;
    try {
      if (!await screen.canSleep()) {
        throw StateError('Cấp quyền tắt màn hình trong Cài đặt → Robot trước.');
      }
      if (preferences.wakeWordEnabled) {
        if (_lastFrame == null ||
            now().difference(_lastFrame!) > const Duration(seconds: 3)) {
          throw StateError('Mic chưa sẵn sàng để nghe từ đánh thức.');
        }
        await detector.prepare(
          preferences.wakePhrase,
          preferences.wakeSensitivity.threshold,
        );
      }
      if (_disposed ||
          !_foreground ||
          (!manual && (generation != _activityGeneration || _busy))) {
        return;
      }
      sleeping = true;
      suspended = true;
      await setStandby(true);
      detector.reset();
      if (preferences.wakeWordEnabled) {
        await screen.startLocalListening(preferences.wakePhrase);
      }
      await screen.sleep();
      _micHealth?.cancel();
      _micHealth = Timer.periodic(const Duration(seconds: 2), (_) {
        if (sleeping &&
            preferences.wakeWordEnabled &&
            (_lastFrame == null ||
                now().difference(_lastFrame!) > const Duration(seconds: 6))) {
          error = 'Mic bị gián đoạn; đã bật lại màn hình.';
          unawaited(wake());
        }
      });
    } catch (e) {
      error = 'Không chuyển sang nghỉ được: $e';
      if (!_disposed) {
        sleeping = false;
        if (suspended) {
          await screen.stopLocalListening();
          await setStandby(false);
        }
      }
    } finally {
      transitioning = false;
      if (!_disposed) {
        notifyListeners();
        if (_wakePending) {
          _wakePending = false;
          unawaited(wake());
        } else if (!sleeping) {
          _arm();
        }
      }
    }
  }

  Future<void> wake() async {
    if (_disposed) return;
    if (transitioning) {
      _wakePending = true;
      return;
    }
    if (!sleeping) {
      activity();
      return;
    }
    transitioning = true;
    _micHealth?.cancel();
    try {
      await screen.wake();
      detector.reset();
      await screen.stopLocalListening();
      // Keep the wake phrase's trailing syllable out of the remote ASR.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (_disposed) return;
      await setStandby(false);
      sleeping = false;
    } catch (e) {
      error = 'Không đánh thức được: $e';
    } finally {
      transitioning = false;
      _wakePending = false;
      if (!_disposed) {
        notifyListeners();
        if (!sleeping) _arm();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && sleeping) {
      unawaited(wake());
    } else if (_foreground) {
      activity();
    } else {
      _idle?.cancel();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _idle?.cancel();
    _micHealth?.cancel();
    preferences.removeListener(_settingsChanged);
    voice.removeListener(_voiceChanged);
    playback.removeListener(_voiceChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_frames?.cancel());
    unawaited(detector.dispose());
    unawaited(screen.stopLocalListening());
    super.dispose();
  }
}
