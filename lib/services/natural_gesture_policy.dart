import 'robot_preferences.dart';

enum NaturalGesture { acknowledge, thinking, joyful, sad, surprised }

/// Profile values are deliberately sparse: silence is a valid response.
abstract final class NaturalGesturePolicy {
  static Duration headRest(GestureIntensity profile) =>
      Duration(seconds: profile == GestureIntensity.lively ? 15 : 24);
  static Duration wheelRest(GestureIntensity profile) =>
      Duration(seconds: profile == GestureIntensity.lively ? 30 : 45);
  static double chance(NaturalGesture kind, GestureIntensity profile) {
    if (profile == GestureIntensity.off) return 0;
    final lively = profile == GestureIntensity.lively;
    return switch (kind) {
      NaturalGesture.acknowledge => lively ? .55 : .3,
      NaturalGesture.thinking => lively ? .4 : .2,
      NaturalGesture.joyful => lively ? .75 : .5,
      NaturalGesture.sad => lively ? .3 : .15,
      NaturalGesture.surprised => lively ? .5 : .3,
    };
  }

  static bool isJoyful(String emotion) =>
      emotion == 'happy' || emotion == 'funny';
  static bool isAgreement(String text) => RegExp(
    r'^(vâng|ừ|ừm|đúng rồi|đúng vậy|đồng ý|được rồi|chính xác)(?=$|[\s,.!?…])',
    caseSensitive: false,
  ).hasMatch(text.trim());

  static NaturalGesture? speakingCue(String emotion, String text) {
    if (isAgreement(text)) return NaturalGesture.acknowledge;
    return switch (emotion) {
      'happy' || 'funny' => NaturalGesture.joyful,
      'frustrated' || 'cry' => NaturalGesture.sad,
      'surprised' => NaturalGesture.surprised,
      _ => null,
    };
  }
}
