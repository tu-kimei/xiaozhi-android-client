import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/natural_gesture_policy.dart';
import 'package:ai_assistant/services/robot_preferences.dart';

void main() {
  test('only actual agreement or expressive emotion gets a speaking cue', () {
    expect(
      NaturalGesturePolicy.speakingCue('default', 'Mình kể cho bạn nghe nhé.'),
      isNull,
    );
    expect(
      NaturalGesturePolicy.speakingCue('default', 'Đúng rồi, mình đồng ý!'),
      NaturalGesture.acknowledge,
    );
    expect(
      NaturalGesturePolicy.speakingCue('happy', 'Tuyệt quá!'),
      NaturalGesture.joyful,
    );
    expect(NaturalGesturePolicy.isAgreement('Mình chưa đồng ý.'), isFalse);
    expect(NaturalGesturePolicy.isAgreement('Đúng ra còn cách khác.'), isFalse);
    expect(
      NaturalGesturePolicy.isJoyful('enjoy'),
      isFalse,
    ); // Relaxed is not excited.
    expect(NaturalGesturePolicy.isJoyful('funny'), isTrue);
  });
  test(
    'profiles keep bounded nonzero rests and quiet has no gesture chance',
    () {
      for (final cue in NaturalGesture.values) {
        expect(NaturalGesturePolicy.chance(cue, GestureIntensity.off), 0);
        expect(
          NaturalGesturePolicy.chance(cue, GestureIntensity.gentle),
          lessThan(1),
        );
        expect(
          NaturalGesturePolicy.chance(cue, GestureIntensity.lively),
          greaterThan(
            NaturalGesturePolicy.chance(cue, GestureIntensity.gentle),
          ),
        );
      }
      expect(
        NaturalGesturePolicy.headRest(GestureIntensity.gentle).inSeconds,
        24,
      );
      expect(
        NaturalGesturePolicy.headRest(GestureIntensity.lively).inSeconds,
        15,
      );
      expect(
        NaturalGesturePolicy.wheelRest(GestureIntensity.gentle).inSeconds,
        45,
      );
    },
  );
}
