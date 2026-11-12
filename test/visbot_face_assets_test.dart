import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/face_controller.dart';
import 'package:ai_assistant/services/visbot_face_assets.dart';

void main() {
  test('all 21 Xiaozhi emotions map to on-device Visbot names', () {
    const expected = {
      'neutral': 'default',
      'happy': 'happy',
      'laughing': 'funny',
      'funny': 'funny',
      'sad': 'frustrated',
      'angry': 'mad',
      'crying': 'cry',
      'loving': 'love',
      'embarrassed': 'shy',
      'surprised': 'surprised',
      'shocked': 'surprised',
      'thinking': 'doubt',
      'winking': 'confidence',
      'cool': 'confidence',
      'relaxed': 'enjoy',
      'delicious': 'desire',
      'kissy': 'love',
      'confident': 'confidence',
      'sleepy': 'fatigue',
      'silly': 'funny',
      'confused': 'doubt',
    };
    for (final e in expected.entries) {
      expect(FaceController.mapVisbotEmotion(e.key), e.value);
    }
    expect(FaceController.mapVisbotEmotion(' HAPPY '), 'happy');
    expect(FaceController.mapVisbotEmotion('../../file'), 'default');
  });
  test(
    'file resolution uses silent/speaking pairs and safely falls back',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'visbot-face-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final silent = await Directory('${directory.path}/bushuohua').create();
      final speaking = await Directory('${directory.path}/shuohua').create();
      await File('${silent.path}/silent_default_1.svga').writeAsBytes([1]);
      await File('${speaking.path}/speak_happy_1.svga').writeAsBytes([2]);
      final assets = VisbotFaceAssets(root: directory.path);
      expect(
        await assets.resolve('happy', true),
        '${speaking.path}/speak_happy_1.svga',
      );
      expect(
        await assets.resolve('happy', false),
        '${silent.path}/silent_default_1.svga',
      );
      expect(await assets.resolve('../happy', true), isNull);
      expect(await assets.resolve('cry', true), isNull);
      expect(
        await const VisbotFaceAssets(
          root: '/missing-visbot-system',
        ).resolve('default', false),
        isNull,
      );
    },
  );
}
