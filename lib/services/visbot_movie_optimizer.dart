import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:svgaplayer_3/svgaplayer_flutter.dart';

/// Bound GPU uploads to the display size instead of the source's 640x500
/// textures. Decode sequentially to avoid a second full set of large bitmaps.
Future<void> optimizeVisbotMovie(
  MovieEntity movie,
  ui.Size physicalSize,
) async {
  final width = movie.params.viewBoxWidth;
  final height = movie.params.viewBoxHeight;
  if (width <= 0 || height <= 0 || physicalSize.isEmpty) return;
  final scale = math.min(
    physicalSize.width / width,
    physicalSize.height / height,
  );
  if (scale >= 1 || !scale.isFinite) return;
  for (final key in movie.bitmapCache.keys.toList()) {
    final original = movie.bitmapCache[key]!;
    final bytes = movie.images[key];
    if (bytes == null || bytes.isEmpty) continue;
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
        targetWidth: math.max(1, (original.width * scale).ceil()),
        targetHeight: math.max(1, (original.height * scale).ceil()),
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      movie.bitmapCache[key] = frame.image;
      original.dispose();
    } catch (_) {
      // The normal parser may support resources which are not plain images.
      // Keep its decoded resource when the thumbnail decoder cannot read it.
    } finally {
      codec?.dispose();
    }
  }
}
