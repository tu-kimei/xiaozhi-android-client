import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:svgaplayer_3/svgaplayer_flutter.dart';
import '../services/face_controller.dart';
import '../services/visbot_face_assets.dart';
import '../services/visbot_movie_optimizer.dart';
import 'face_view.dart';
import '../utils/pcm_stream_player.dart';

/// One decoded movie at a time; missing/unreadable files use our simple face.
class VisbotFaceView extends StatefulWidget {
  final FaceController controller;
  final VoidCallback? onTap;
  final VisbotFaceAssets assets;
  final ValueListenable<double>? mouthLevel;
  const VisbotFaceView({
    super.key,
    required this.controller,
    this.onTap,
    this.assets = const VisbotFaceAssets(),
    this.mouthLevel,
  });
  @override
  State<VisbotFaceView> createState() => _VisbotFaceViewState();
}

class _VisbotFaceViewState extends State<VisbotFaceView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final SVGAAnimationController _animation;
  String _key = '';
  bool _ready = false;
  bool _unavailable = false;
  int _loadToken = 0;
  Timer? _frames;
  final _elapsed = Stopwatch();

  void _startFrames() {
    _frames?.cancel();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_ready ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    _elapsed.start();
    // The robot cannot rasterize these movies at the display's 58 Hz. Keep
    // the movie's original speed but sample it at 20 fps to leave room for audio.
    _frames = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final duration = _animation.duration?.inMilliseconds ?? 0;
      if (duration > 0 && mounted) {
        _animation.value = (_elapsed.elapsedMilliseconds % duration) / duration;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startFrames();
    } else {
      _frames?.cancel();
      _elapsed.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _animation = SVGAAnimationController(vsync: this);
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(VisbotFaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _key = '';
      _changed();
    }
  }

  void _changed() {
    final face = widget.controller;
    final key = face.visbotEmotion;
    if (key == _key) {
      if (mounted) setState(() {});
      return;
    }
    _key = key;
    final token = ++_loadToken;
    // Keep the existing Visbot eyes visible while decoding the next emotion.
    // Silent movies supply the eyes; the mouth follows actual output RMS.
    _load(face.visbotEmotion, token);
    if (mounted) setState(() {});
  }

  Future<void> _load(String emotion, int token) async {
    try {
      final path = await widget.assets.resolve(emotion, false);
      if (!mounted || token != _loadToken) return;
      if (path == null) {
        setState(() => _unavailable = true);
        return;
      }
      final movie = await SVGAParser.shared.decodeFromBuffer(
        await File(path).readAsBytes(),
      );
      if (mounted && token == _loadToken) {
        final media = MediaQuery.of(context);
        await optimizeVisbotMovie(movie, media.size * media.devicePixelRatio);
      }
      if (!mounted || token != _loadToken) {
        movie.dispose();
        return;
      }
      _frames?.cancel();
      _elapsed.reset();
      _animation.videoItem = movie;
      setState(() => _ready = true);
      _startFrames();
    } catch (e) {
      debugPrint('VisbotFaceView: fallback to simple face: $e');
      if (mounted && token == _loadToken) setState(() => _unavailable = true);
    }
  }

  @override
  void dispose() {
    ++_loadToken;
    WidgetsBinding.instance.removeObserver(this);
    _frames?.cancel();
    _elapsed.stop();
    widget.controller.removeListener(_changed);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    behavior: HitTestBehavior.opaque,
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_ready && _unavailable) FaceView(controller: widget.controller),
          AnimatedOpacity(
            opacity: _ready ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: RepaintBoundary(
              child: SVGAImage(
                _animation,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                allowDrawingOverflow: false,
              ),
            ),
          ),
          if (_ready && widget.controller.isSpeaking)
            IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable:
                    widget.mouthLevel ?? PcmStreamPlayer.playbackLevel,
                builder:
                    (context, level, _) =>
                        CustomPaint(painter: _VisbotMouthPainter(level)),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Replace the silent movie's lower lip only while real audio is playing.
class _VisbotMouthPainter extends CustomPainter {
  final double level;
  const _VisbotMouthPainter(this.level);

  @override
  void paint(Canvas canvas, Size size) {
    final width =
        size.width / size.height > 1.28 ? size.height * 1.28 : size.width;
    final height = width / 1.28;
    final left = (size.width - width) / 2;
    final top = (size.height - height) / 2;
    canvas.drawRect(
      Rect.fromLTWH(left, top + height * .77, width, height * .23),
      Paint()..color = Colors.black,
    );
    final center = Offset(size.width / 2, top + height * .84);
    final halfWidth = width * .085;
    final open = height * .065 * level;
    final mouth =
        Path()
          ..moveTo(center.dx - halfWidth, center.dy)
          ..quadraticBezierTo(
            center.dx,
            center.dy + 8 + open,
            center.dx + halfWidth,
            center.dy,
          )
          ..quadraticBezierTo(
            center.dx,
            center.dy + 8 - open,
            center.dx - halfWidth,
            center.dy,
          );
    canvas.drawPath(
      mouth,
      Paint()
        ..color = const Color(0xFFFF929C)
        ..style = level > .05 ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_VisbotMouthPainter oldDelegate) =>
      oldDelegate.level != level;
}
