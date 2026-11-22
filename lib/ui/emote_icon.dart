import 'package:flutter/material.dart';

/// Emoji faces rendered as vectors so Linux doesn't depend on emoji-font glyphs.
class GameEmoteIcon extends StatelessWidget {
  const GameEmoteIcon(this.emoji, {super.key, this.size = 24});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (emoji != '😄' && emoji != '😏') {
      return Text(emoji, style: TextStyle(fontSize: size));
    }
    return Semantics(
      label: emoji == '😄' ? 'Laughing face' : 'Smug face',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _FacePainter(smug: emoji == '😏')),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  const _FacePainter({required this.smug});
  final bool smug;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    const center = Offset(50, 50);
    canvas.drawCircle(center, 47, Paint()..color = const Color(0xffffc83d));
    canvas.drawCircle(
      const Offset(41, 31),
      31,
      Paint()..color = const Color(0x44fff6bd),
    );
    final ink = Paint()
      ..color = const Color(0xff643b22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.2
      ..strokeCap = StrokeCap.round;
    if (smug) {
      // Asymmetric, half-lidded eyes and a crooked smirk.
      canvas.drawPath(
        Path()
          ..moveTo(21, 39)
          ..quadraticBezierTo(31, 32, 42, 39)
          ..moveTo(60, 38)
          ..quadraticBezierTo(71, 31, 81, 36),
        ink,
      );
      canvas.drawCircle(
        const Offset(33, 42),
        2.8,
        Paint()..color = const Color(0xff643b22),
      );
      canvas.drawCircle(
        const Offset(72, 40),
        2.8,
        Paint()..color = const Color(0xff643b22),
      );
      canvas.drawPath(
        Path()
          ..moveTo(30, 63)
          ..quadraticBezierTo(53, 79, 77, 56)
          ..quadraticBezierTo(66, 76, 47, 76),
        ink..strokeWidth = 5.8,
      );
    } else {
      // Laughing eyes, wide dark mouth and clearly readable white teeth.
      canvas.drawPath(
        Path()
          ..moveTo(19, 39)
          ..quadraticBezierTo(31, 24, 43, 39)
          ..moveTo(59, 39)
          ..quadraticBezierTo(71, 24, 83, 39),
        ink,
      );
      final mouth = Path()
        ..moveTo(20, 58)
        ..quadraticBezierTo(49, 47, 80, 58)
        ..quadraticBezierTo(74, 91, 50, 91)
        ..quadraticBezierTo(26, 90, 20, 58)
        ..close();
      canvas.drawPath(mouth, Paint()..color = const Color(0xff63311e));
      canvas.drawPath(
        Path()
          ..moveTo(25, 59)
          ..quadraticBezierTo(50, 55, 75, 59)
          ..quadraticBezierTo(72, 69, 49, 69)
          ..quadraticBezierTo(30, 68, 25, 59)
          ..close(),
        Paint()..color = Colors.white,
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(51, 87), width: 31, height: 10),
        Paint()..color = const Color(0xffea736f),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FacePainter oldDelegate) =>
      oldDelegate.smug != smug;
}
