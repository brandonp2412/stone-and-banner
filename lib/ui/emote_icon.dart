import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Custom emoji faces that look the same across platforms.
class GameEmoteIcon extends StatelessWidget {
  const GameEmoteIcon(this.emoji, {super.key, this.size = 24});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final expression = switch (emoji) {
      '😄' => _Expression.laugh,
      '😏' => _Expression.smirk,
      '😈' => _Expression.devil,
      _ => null,
    };
    if (expression == null) {
      return Text(emoji, style: TextStyle(fontSize: size));
    }
    final useSystemEmoji =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
    return Semantics(
      label: expression.label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: useSystemEmoji
            ? Center(
                child: Text(
                  emoji,
                  style: TextStyle(
                    fontFamily: 'Noto Color Emoji',
                    fontSize: size,
                    height: 1,
                  ),
                  textScaler: TextScaler.noScaling,
                ),
              )
            : CustomPaint(painter: _FacePainter(expression)),
      ),
    );
  }
}

enum _Expression {
  laugh('Laughing face'),
  smirk('Cheeky face'),
  devil('Cheeky devil emoji');

  const _Expression(this.label);

  final String label;
}

class _FacePainter extends CustomPainter {
  const _FacePainter(this.expression);

  static const _textureSize = 256;
  static final _textures = <_Expression, ui.Image>{};

  final _Expression expression;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;

    // Filter the supersampled faces when the badge or its animation shrinks them.
    final texture = _textures.putIfAbsent(expression, _rasterize);
    canvas.drawImageRect(
      texture,
      const Rect.fromLTWH(0, 0, _textureSize * 1.0, _textureSize * 1.0),
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: side,
        height: side,
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  ui.Image _rasterize() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_textureSize / 100);
    _drawFace(canvas);
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(_textureSize, _textureSize);
    } finally {
      picture.dispose();
    }
  }

  void _drawFace(Canvas canvas) {
    final devil = expression == _Expression.devil;
    final center = Offset(50, devil ? 56 : 50);
    final radius = devil ? 40.0 : 46.0;
    final fill = Paint();

    if (devil) {
      final horns = Path()
        ..moveTo(15, 39)
        ..quadraticBezierTo(9, 21, 17, 5)
        ..quadraticBezierTo(25, 19, 39, 23)
        ..close()
        ..moveTo(85, 39)
        ..quadraticBezierTo(91, 21, 83, 5)
        ..quadraticBezierTo(75, 19, 61, 23)
        ..close();
      canvas.drawPath(horns, fill..color = const Color(0xffeb8f00));
    }

    // Match the saturated yellow/gold of the native hand and face emoji.
    // A darker lower rim provides depth without turning the whole face orange.
    canvas.drawCircle(center, radius, fill..color = const Color(0xffeb8f00));
    final surfaceCenter = center.translate(0, -1.5);
    final surfaceRadius = radius - 1.5;
    canvas.drawCircle(
      surfaceCenter,
      surfaceRadius,
      Paint()
        ..shader =
            const RadialGradient(
              center: Alignment(0, -.10),
              radius: .54,
              colors: [
                Color(0xfffde030),
                Color(0xfffde030),
                Color(0xfff9c92c),
                Color(0xfff4a621),
              ],
              stops: [0, .42, .83, 1],
            ).createShader(
              Rect.fromCircle(center: surfaceCenter, radius: surfaceRadius),
            ),
    );

    const featureColor = Color(0xff35220b);
    final stroke = Paint()
      ..color = featureColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    switch (expression) {
      case _Expression.laugh:
        canvas.drawPath(
          Path()
            ..moveTo(22, 42)
            ..quadraticBezierTo(32, 27, 42, 42)
            ..moveTo(58, 42)
            ..quadraticBezierTo(68, 27, 78, 42),
          stroke,
        );
        final mouth = Path()
          ..moveTo(22, 56)
          ..quadraticBezierTo(50, 60, 78, 56)
          ..cubicTo(76, 72, 65, 85, 50, 85)
          ..cubicTo(35, 85, 24, 72, 22, 56)
          ..close();
        canvas.drawPath(mouth, fill..color = featureColor);
        canvas.save();
        canvas.clipPath(mouth);
        canvas.drawPath(
          Path()
            ..moveTo(23, 55)
            ..lineTo(77, 55)
            ..lineTo(74, 63)
            ..quadraticBezierTo(50, 71, 26, 63)
            ..close(),
          fill..color = const Color(0xfffff9ed),
        );
        canvas.drawOval(
          const Rect.fromLTWH(36, 76, 28, 16),
          fill..color = const Color(0xffe87873),
        );
        canvas.restore();
      case _Expression.smirk:
        // Relaxed, slightly raised brows and a deliberate sideways glance.
        canvas.drawPath(
          Path()
            ..moveTo(19, 35)
            ..quadraticBezierTo(25, 29, 34, 29)
            ..moveTo(66, 29)
            ..quadraticBezierTo(75, 29, 81, 35),
          stroke..strokeWidth = 3.7,
        );
        canvas.drawPath(
          Path()
            ..moveTo(22, 45)
            ..quadraticBezierTo(31, 40, 41, 44)
            ..moveTo(59, 44)
            ..quadraticBezierTo(68, 40, 78, 45),
          stroke..strokeWidth = 4.4,
        );
        fill.color = featureColor;
        canvas.drawOval(const Rect.fromLTWH(31, 43, 10, 11), fill);
        canvas.drawOval(const Rect.fromLTWH(68, 43, 10, 11), fill);
        // A nearly level closed mouth that curls up on only one side.
        canvas.drawPath(
          Path()
            ..moveTo(36, 77)
            ..cubicTo(51, 79, 70, 77, 72, 66),
          stroke..strokeWidth = 6.2,
        );
      case _Expression.devil:
        final eyes = Path()
          ..moveTo(23, 43)
          ..lineTo(45, 52)
          ..quadraticBezierTo(36, 69, 27, 57)
          ..close()
          ..moveTo(77, 43)
          ..lineTo(55, 52)
          ..quadraticBezierTo(64, 69, 73, 57)
          ..close();
        canvas.drawPath(eyes, fill..color = featureColor);
        canvas.drawPath(
          Path()
            ..moveTo(30, 70)
            ..quadraticBezierTo(50, 85, 70, 68),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _FacePainter oldDelegate) =>
      oldDelegate.expression != expression;
}
