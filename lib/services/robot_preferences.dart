import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'standby/wake_phrase_tokenizer.dart';

enum GestureIntensity { off, gentle, lively }

enum WakeSensitivity {
  low(.35),
  normal(.25),
  high(.16);

  final double threshold;
  const WakeSensitivity(this.threshold);
}

enum VoiceSensitivity {
  low(54, 9),
  normal(50, 6),
  high(44, 4);

  final double minSpeechDb;
  final double marginDb;
  const VoiceSensitivity(this.minSpeechDb, this.marginDb);
}

/// Settings shared by call UI, movement policy and local speech detection.
class RobotPreferences extends ChangeNotifier {
  static final instance = RobotPreferences();
  Future<void>? _loading;
  bool voiceEnabled = false;
  bool wheelsEnabled = false;
  bool autoSleep = true;
  int sleepSeconds = 300;
  bool wakeWordEnabled = true;
  String wakePhrase = 'Hey Doradino';
  WakeSensitivity wakeSensitivity = WakeSensitivity.normal;
  bool faceEnabled = true;
  String faceStyle = 'simple';
  int headSpeed = 25;
  int wheelSpeed = 10;
  int turnSpeed = 120;
  int nodCount = 3;
  int nodAngle = 18;
  VoiceSensitivity sensitivity = VoiceSensitivity.normal;
  int silenceMs = 780;
  GestureIntensity gestures = GestureIntensity.gentle;
  bool swayWhenSpeaking = false;
  bool moveWhenConversing = false;
  int stepMs = 500;
  int rotationMs = 1500;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    voiceEnabled = p.getBool('robot_voice') ?? false;
    wheelsEnabled = p.getBool('robot_wheels') ?? false;
    autoSleep = p.getBool('robot_auto_sleep') ?? true;
    sleepSeconds = (p.getInt('robot_sleep_seconds') ?? 300).clamp(60, 1800);
    wakeWordEnabled = p.getBool('robot_wake_enabled') ?? true;
    final storedPhrase = p.getString('robot_wake_phrase') ?? 'Hey Doradino';
    wakePhrase =
        WakePhraseTokenizer.valid(storedPhrase) ? storedPhrase : 'Hey Doradino';
    wakeSensitivity =
        WakeSensitivity.values[(p.getInt('robot_wake_sensitivity') ?? 1).clamp(
          0,
          2,
        )];
    faceEnabled = p.getBool('face_enabled') ?? true;
    faceStyle = p.getString('face_style') == 'visbot' ? 'visbot' : 'simple';
    final oldMedium = p.getBool('robot_medium_speed') ?? false;
    headSpeed = (p.getInt('robot_head_speed') ?? 25).clamp(10, 30);
    wheelSpeed = (p.getInt('robot_wheel_speed') ?? (oldMedium ? 15 : 10)).clamp(
      1,
      15,
    );
    turnSpeed = (p.getInt('robot_turn_speed') ?? (oldMedium ? 200 : 120)).clamp(
      16,
      200,
    );
    nodCount = (p.getInt('robot_nod_count') ?? 3).clamp(1, 3);
    nodAngle = (p.getInt('robot_nod_angle') ?? 18).clamp(5, 20);
    sensitivity =
        VoiceSensitivity.values[(p.getInt('robot_sensitivity') ?? 1).clamp(
          0,
          2,
        )];
    silenceMs = (p.getInt('robot_silence_ms') ?? 780).clamp(300, 1500);
    gestures =
        GestureIntensity.values[(p.getInt('robot_gestures') ?? 1).clamp(0, 2)];
    swayWhenSpeaking = p.getBool('robot_sway') ?? false;
    moveWhenConversing = p.getBool('robot_auto_move') ?? false;
    stepMs = (p.getInt('robot_step_ms') ?? 500).clamp(100, 1000);
    rotationMs = (p.getInt('robot_rotation_ms') ?? 1500).clamp(500, 6000);
    notifyListeners();
  }

  Future<void> update({
    bool? voice,
    bool? wheels,
    String? face,
    bool? showFace,
    bool? sleep,
    int? sleepAfter,
    bool? wakeEnabled,
    String? phrase,
    WakeSensitivity? wakeSense,
    int? head,
    int? speed,
    int? turn,
    int? nods,
    int? amplitude,
    VoiceSensitivity? mic,
    int? silence,
    GestureIntensity? intensity,
    bool? sway,
    bool? autoMove,
    int? step,
    int? rotation,
  }) async {
    await load();
    if (phrase != null && !WakePhraseTokenizer.valid(phrase)) {
      throw ArgumentError('Từ đánh thức cần 2–5 từ tiếng Anh.');
    }
    voiceEnabled = voice ?? voiceEnabled;
    wheelsEnabled = wheels ?? wheelsEnabled;
    autoSleep = sleep ?? autoSleep;
    sleepSeconds = (sleepAfter ?? sleepSeconds).clamp(60, 1800);
    wakeWordEnabled = wakeEnabled ?? wakeWordEnabled;
    wakePhrase = phrase?.trim() ?? wakePhrase;
    wakeSensitivity = wakeSense ?? wakeSensitivity;
    faceEnabled = showFace ?? faceEnabled;
    if (face != null) faceStyle = face == 'visbot' ? 'visbot' : 'simple';
    headSpeed = (head ?? headSpeed).clamp(10, 30);
    wheelSpeed = (speed ?? wheelSpeed).clamp(1, 15);
    turnSpeed = (turn ?? turnSpeed).clamp(16, 200);
    nodCount = (nods ?? nodCount).clamp(1, 3);
    nodAngle = (amplitude ?? nodAngle).clamp(5, 20);
    sensitivity = mic ?? sensitivity;
    silenceMs = (silence ?? silenceMs).clamp(300, 1500);
    gestures = intensity ?? gestures;
    swayWhenSpeaking = sway ?? swayWhenSpeaking;
    moveWhenConversing = autoMove ?? moveWhenConversing;
    stepMs = (step ?? stepMs).clamp(100, 1000);
    rotationMs = (rotation ?? rotationMs).clamp(500, 6000);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setBool('robot_voice', voiceEnabled),
      p.setBool('robot_wheels', wheelsEnabled),
      p.setBool('robot_auto_sleep', autoSleep),
      p.setInt('robot_sleep_seconds', sleepSeconds),
      p.setBool('robot_wake_enabled', wakeWordEnabled),
      p.setString('robot_wake_phrase', wakePhrase),
      p.setInt('robot_wake_sensitivity', wakeSensitivity.index),
      p.setBool('face_enabled', faceEnabled),
      p.setString('face_style', faceStyle),
      p.setInt('robot_head_speed', headSpeed),
      p.setInt('robot_wheel_speed', wheelSpeed),
      p.setInt('robot_turn_speed', turnSpeed),
      p.setInt('robot_nod_count', nodCount),
      p.setInt('robot_nod_angle', nodAngle),
      p.setInt('robot_sensitivity', sensitivity.index),
      p.setInt('robot_silence_ms', silenceMs),
      p.setInt('robot_gestures', gestures.index),
      p.setBool('robot_sway', swayWhenSpeaking),
      p.setBool('robot_auto_move', moveWhenConversing),
      p.setInt('robot_step_ms', stepMs),
      p.setInt('robot_rotation_ms', rotationMs),
    ]);
  }

  Future<void> reset() => update(
    voice: false,
    wheels: false,
    face: 'simple',
    showFace: true,
    sleep: true,
    sleepAfter: 300,
    wakeEnabled: true,
    phrase: 'Hey Doradino',
    wakeSense: WakeSensitivity.normal,
    head: 25,
    speed: 10,
    turn: 120,
    nods: 3,
    amplitude: 18,
    mic: VoiceSensitivity.normal,
    silence: 780,
    intensity: GestureIntensity.gentle,
    sway: false,
    autoMove: false,
    step: 500,
    rotation: 1500,
  );
}
