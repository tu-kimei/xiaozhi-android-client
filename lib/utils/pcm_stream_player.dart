import 'package:flutter/services.dart';

/// Dart side of the app's native PcmStreamPlayer (16-bit mono PCM).
///
/// Same method names as flutter_pcm_player, but the native AudioTrack has a
/// 4x buffer and an URGENT_AUDIO writer thread so replies don't stutter.
class PcmStreamPlayer {
  static const _channel = MethodChannel('xiaozhi/pcm_player');

  Future<void> initialize({required int sampleRate}) =>
      _channel.invokeMethod('initialize', {'sampleRate': sampleRate});

  Future<void> play() => _channel.invokeMethod('play');

  /// Drops queued audio immediately; the player stays ready for more.
  Future<void> stop() => _channel.invokeMethod('stop');

  Future<void> feed(Uint8List pcm) =>
      _channel.invokeMethod('feed', {'data': pcm});

  Future<void> release() => _channel.invokeMethod('release');
}
