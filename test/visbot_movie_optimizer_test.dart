import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:svgaplayer_3/svgaplayer_flutter.dart';
import 'package:ai_assistant/services/visbot_movie_optimizer.dart';

void main() {
  testWidgets(
    'SVGA textures are downsampled to display size without changing geometry',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const ui.Rect.fromLTWH(0, 0, 200, 100),
          ui.Paint()..color = const ui.Color(0xffffffff),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(200, 100);
        picture.dispose();
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final movie = MovieEntity(
          params: MovieParams(
            viewBoxWidth: 200,
            viewBoxHeight: 100,
            fps: 20,
            frames: 1,
          ),
          images: {'face': data.buffer.asUint8List()},
        );
        movie.bitmapCache['face'] = image;
        await optimizeVisbotMovie(movie, const ui.Size(100, 50));
        expect(movie.bitmapCache['face']!.width, 100);
        expect(movie.bitmapCache['face']!.height, 50);
        expect(movie.params.viewBoxWidth, 200);
        expect(movie.params.viewBoxHeight, 100);
        final thumbnail = movie.bitmapCache['face'];
        await optimizeVisbotMovie(movie, const ui.Size(400, 200));
        expect(
          movie.bitmapCache['face'],
          same(thumbnail),
        ); // no upscaling/redecode
        movie.dispose();
      });
    },
  );
}
