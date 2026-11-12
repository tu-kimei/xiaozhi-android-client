import 'dart:async';

import 'package:ai_assistant/utils/pcm_stream_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xiaozhi/pcm_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> outputEvent(String method, dynamic value) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, value)),
      (_) => done.complete(),
    );
    await done.future;
  }

  Future<void> outputState(bool active) => outputEvent('playbackState', active);

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'Only native output progress opens the mouth; stop and release reset it',
    () async {
      final player = PcmStreamPlayer();
      await player.initialize(sampleRate: 24000);
      await player.play();
      await player.feed(Uint8List(28800));
      expect(PcmStreamPlayer.playbackActive.value, isFalse);
      await outputState(true);
      expect(PcmStreamPlayer.playbackActive.value, isTrue);
      await outputState(false); // output stalled / drained
      expect(PcmStreamPlayer.playbackActive.value, isFalse);
      await outputState(true);
      await player.stop();
      expect(PcmStreamPlayer.playbackActive.value, isFalse);
      await outputState(true);
      await player.release();
      expect(PcmStreamPlayer.playbackActive.value, isFalse);
    },
  );
  test(
    'mouth level follows audible RMS, ignores queued levels and resets',
    () async {
      final player = PcmStreamPlayer();
      await player.stop();
      await outputEvent('playbackLevel', .7);
      expect(PcmStreamPlayer.playbackLevel.value, 0);
      await outputState(true);
      await outputEvent('playbackLevel', .7);
      expect(PcmStreamPlayer.playbackLevel.value, .7);
      await outputEvent('playbackLevel', 0.0); // silence inside a sentence
      expect(PcmStreamPlayer.playbackLevel.value, 0);
      await outputEvent('playbackLevel', 2.0);
      expect(PcmStreamPlayer.playbackLevel.value, 1);
      await outputState(false);
      expect(PcmStreamPlayer.playbackLevel.value, 0);
      await outputState(true);
      await outputEvent('playbackLevel', .5);
      await player.stop();
      expect(PcmStreamPlayer.playbackLevel.value, 0);
      await player.release();
    },
  );
}
