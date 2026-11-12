import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ai_assistant/services/visbot_face_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/face_controller.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/widgets/face_view.dart';
import 'package:ai_assistant/widgets/visbot_face_view.dart';

class MissingFaceAssets extends VisbotFaceAssets {
  final resolved = Completer<String?>();
  @override
  Future<String?> resolve(String emotion, bool speaking) => resolved.future;
}

void main() {
  testWidgets(
    'SVGA selection on an ordinary device keeps our tappable fallback',
    (tester) async {
      tester.view.physicalSize = const Size(308, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final voice = ValueNotifier(XiaozhiVoiceState.listening);
      final emotion = ValueNotifier('neutral');
      final playback = ValueNotifier(false);
      final face = FaceController(
        voiceStateListenable: voice,
        emotionListenable: emotion,
        playbackActiveListenable: playback,
      );
      var taps = 0;
      final assets = MissingFaceAssets();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VisbotFaceView(
              controller: face,
              assets: assets,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      expect(
        find.byType(FaceView),
        findsNothing,
      ); // Never flash another face while loading.
      assets.resolved.complete(
        null,
      ); // This device has no Visbot system assets.
      await tester.pump();
      expect(find.byType(FaceView), findsOneWidget);
      await tester.tapAt(const Offset(154, 120));
      expect(taps, 1);
      playback.value = true;
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      face.dispose();
      voice.dispose();
      emotion.dispose();
      playback.dispose();
      await tester.pump(const Duration(seconds: 7));
      expect(tester.takeException(), isNull);
    },
  );
}
