import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_assistant/services/face_controller.dart';

/// 机器人面部视图（Việc 2 — 情绪脸）。
///
/// 用 `CustomPainter` 直接矢量绘制，不依赖 SVGA / Lottie 插件：
/// - 在 Visbot（armeabi-v7a、API 27、308×240）上开销最小，不与解码 Opus 的音频线程抢 CPU；
/// - 在非 Visbot 手机上当“备用脸”，不需要读取 `/system/media/visbot`。
///
/// 只在机器人**正在说话**时运行嘴部动画（`_pulse`），其他状态只有随机眨眼，
/// 空闲时几乎不重绘。
class FaceView extends StatefulWidget {
  final FaceController controller;

  /// 关闭时不绘制任何动画，只留一个纯色背景（设置项用）。
  final bool enabled;

  /// 点击回调（用于显示/隐藏控制栏）。
  final VoidCallback? onTap;

  const FaceView({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onTap,
  });

  @override
  State<FaceView> createState() => _FaceViewState();
}

class _FaceViewState extends State<FaceView>
    with TickerProviderStateMixin {
  static const Duration _blinkDuration = Duration(milliseconds: 150);

  late final AnimationController _blink;
  late final AnimationController _pulse;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: _blinkDuration,
      reverseDuration: _blinkDuration,
    );
    // 说话时的 mouth 开合周期；180ms 一次，肉眼自然、重绘频率又足够低
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    widget.controller.addListener(_onFaceChanged);
    _syncPulse();
    _startBlinkLoop();
  }

  void _onFaceChanged() {
    _syncPulse();
    if (mounted) setState(() {});
  }

  void _syncPulse() {
    final speaking = widget.enabled && widget.controller.isSpeaking;
    if (speaking && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!speaking && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  Future<void> _startBlinkLoop() async {
    while (mounted) {
      await Future<void>.delayed(
        Duration(milliseconds: 2200 + _random.nextInt(3800)),
      );
      if (!mounted || !widget.enabled || widget.controller.isSpeaking) continue;
      await _blink.forward();
      if (!mounted) return;
      await _blink.reverse();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFaceChanged);
    _blink.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AnimatedBuilder(
      animation: Listenable.merge([_blink, _pulse]),
      builder: (context, _) {
        if (!widget.enabled) return const SizedBox.expand();
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onTap,
          child: CustomPaint(
            size: Size.infinite,
            painter: FacePainter(
              emotion: c.currentEmotion,
              isListening: c.isListening,
              isThinking: c.isThinking,
              isSpeaking: c.isSpeaking,
              blink: _blink.value,
              mouthOpen: c.isSpeaking
                  ? 0.25 + 0.75 * _pulse.value.abs()
                  : 0.0,
            ),
          ),
        );
      },
    );
  }
}

/// 表情画笔：两只眼睛 + 一张嘴，全部用路径绘制。
class FacePainter extends CustomPainter {
  final RobotFaceEmotion emotion;
  final bool isListening;
  final bool isThinking;
  final bool isSpeaking;
  final double blink;
  final double mouthOpen;

  const FacePainter({
    required this.emotion,
    required this.isListening,
    required this.isThinking,
    required this.isSpeaking,
    required this.blink,
    required this.mouthOpen,
  });

  static const Color _ink = Color(0xFFFFFDF7);
  static const Color _paper = Color(0xFFFFFDF7);
  static const Color _accent = Color(0xFFFF7A59);

  @override
  void paint(Canvas canvas, Size size) {
    // 背景：柔和的暗色圆形“脸盘”，让表情在深色通话界面里突出
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _paper.withOpacity(0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _paper.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final eyeDx = radius * 0.42;
    final eyeDy = -radius * 0.12;
    final eyeR = radius * 0.20;
    final leftEye = center + Offset(-eyeDx, eyeDy);
    final rightEye = center + Offset(eyeDx, eyeDy);

    _drawEyes(canvas, leftEye, rightEye, eyeR);
    _drawMouth(canvas, center + Offset(0, radius * 0.44), radius);
  }

  void _drawEyes(Canvas canvas, Offset left, Offset right, double r) {
    if (isListening) {
      _drawLidEye(canvas, left, r * 0.85, 1.0 - blink);
      _drawLidEye(canvas, right, r * 0.85, 1.0 - blink);
      return;
    }
    switch (emotion) {
      case RobotFaceEmotion.happy:
        _drawArcEye(canvas, left, r, curveUp: true);
        _drawArcEye(canvas, right, r, curveUp: true);
        break;

      case RobotFaceEmotion.sad:
        _drawArcEye(canvas, left, r, curveUp: false);
        _drawArcEye(canvas, right, r, curveUp: false);
        _drawTear(canvas, right + Offset(r * 0.2, r * 0.9), r * 0.22);
        break;

      case RobotFaceEmotion.angry:
        _drawGlancedEye(canvas, left, r, tilt: 0.45);
        _drawGlancedEye(canvas, right, r, tilt: -0.45);
        _drawBrow(canvas, left, r, tilt: -0.5);
        _drawBrow(canvas, right, r, tilt: 0.5);
        break;

      case RobotFaceEmotion.surprised:
        final open = math.max(0.15, 1.0 - blink) * r * 1.35;
        _drawRingEye(canvas, left, open);
        _drawRingEye(canvas, right, open);
        break;

      case RobotFaceEmotion.thinking:
        _drawDotEye(canvas, left + Offset(r * 0.25, 0), r * 0.55);
        _drawDotEye(canvas, right - Offset(r * 0.25, 0), r * 0.85);
        break;

      case RobotFaceEmotion.sleepy:
        _drawLineEye(canvas, left, r);
        _drawLineEye(canvas, right, r);
        break;

      case RobotFaceEmotion.neutral:
        _drawLidEye(canvas, left, r, 1.0 - blink);
        _drawLidEye(canvas, right, r, 1.0 - blink);
        break;
    }
  }

  Paint get _stroke => Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7
    ..strokeCap = StrokeCap.round;

  Paint get _fill => Paint()
    ..color = _ink
    ..style = PaintingStyle.fill;

  void _drawLidEye(Canvas canvas, Offset c, double r, double lid) {
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 1.5, height: r * 1.5 * lid),
      _fill,
    );
  }

  void _drawRingEye(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r, _stroke);
    canvas.drawCircle(c, r * 0.35, _fill);
  }

  void _drawDotEye(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r, _fill);
  }

  void _drawLineEye(Canvas canvas, Offset c, double r) {
    final p = Path()
      ..moveTo(c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy + r * 0.35, c.dx + r, c.dy);
    canvas.drawPath(p, _stroke);
  }

  void _drawArcEye(Canvas canvas, Offset c, double r, {required bool curveUp}) {
    final bend = curveUp ? -r * 0.75 : r * 0.75;
    final p = Path()
      ..moveTo(c.dx - r, c.dy + (curveUp ? r * 0.25 : -r * 0.15))
      ..quadraticBezierTo(c.dx, c.dy + bend, c.dx + r, c.dy + (curveUp ? r * 0.25 : -r * 0.15));
    canvas.drawPath(p, _stroke);
  }

  void _drawGlancedEye(Canvas canvas, Offset c, double r, {required double tilt}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 1.6, height: r * 1.0),
      _fill,
    );
    canvas.restore();
  }

  void _drawBrow(Canvas canvas, Offset c, double r, {required double tilt}) {
    canvas.save();
    canvas.translate(c.dx, c.dy - r * 1.5);
    canvas.rotate(tilt);
    canvas.drawLine(
      Offset(-r, 0),
      Offset(r, 0),
      Paint()
        ..color = _ink
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _drawTear(Canvas canvas, Offset c, double r) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r, c.dy, c.dx, c.dy - r);
    canvas.drawPath(p, Paint()..color = _accent..style = PaintingStyle.fill);
  }

  void _drawMouth(Canvas canvas, Offset c, double radius) {
    final width = radius * 0.62;
    if (isListening) {
      final smile = Path()
        ..moveTo(c.dx - width * 0.35, c.dy)
        ..quadraticBezierTo(
          c.dx, c.dy + radius * 0.10, c.dx + width * 0.35, c.dy,
        );
      canvas.drawPath(smile, _stroke);
      return;
    }
    if (isSpeaking) {
      final h = radius * 0.10 + mouthOpen * radius * 0.34;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: width, height: h),
          Radius.circular(h * 0.5),
        ),
        _fill,
      );
      return;
    }

    switch (emotion) {
      case RobotFaceEmotion.happy:
        final p = Path()
          ..moveTo(c.dx - width * 0.6, c.dy - radius * 0.02)
          ..quadraticBezierTo(c.dx, c.dy + radius * 0.30, c.dx + width * 0.6, c.dy - radius * 0.02);
        canvas.drawPath(p, _stroke);
        break;

      case RobotFaceEmotion.sad:
      case RobotFaceEmotion.angry:
        final p = Path()
          ..moveTo(c.dx - width * 0.55, c.dy + radius * 0.10)
          ..quadraticBezierTo(c.dx, c.dy - radius * 0.20, c.dx + width * 0.55, c.dy + radius * 0.10);
        canvas.drawPath(p, _stroke);
        break;

      case RobotFaceEmotion.surprised:
        canvas.drawCircle(c, radius * 0.13, _stroke);
        break;

      case RobotFaceEmotion.thinking:
        canvas.drawCircle(c + Offset(width * 0.3, 0), radius * 0.06, _fill);
        canvas.drawLine(
          Offset(c.dx - width * 0.5, c.dy),
          Offset(c.dx + width * 0.15, c.dy),
          _stroke,
        );
        break;

      case RobotFaceEmotion.sleepy:
        final p = Path()
          ..moveTo(c.dx - width * 0.4, c.dy)
          ..quadraticBezierTo(c.dx - width * 0.2, c.dy + radius * 0.06, c.dx, c.dy)
          ..quadraticBezierTo(c.dx + width * 0.2, c.dy - radius * 0.06, c.dx + width * 0.4, c.dy);
        canvas.drawPath(p, _stroke);
        break;

      case RobotFaceEmotion.neutral:
        canvas.drawLine(
          Offset(c.dx - width * 0.45, c.dy),
          Offset(c.dx + width * 0.45, c.dy),
          _stroke,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(FacePainter old) =>
      old.emotion != emotion ||
      old.isListening != isListening ||
      old.isThinking != isThinking ||
      old.isSpeaking != isSpeaking ||
      old.blink != blink ||
      old.mouthOpen != mouthOpen;
}
