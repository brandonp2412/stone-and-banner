import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Presentation only: the caller supplies the engine's saved dice result.
class DiceRoll extends StatefulWidget {
  const DiceRoll({
    super.key,
    required this.first,
    required this.second,
    this.onComplete,
  });

  final int first;
  final int second;
  final VoidCallback? onComplete;

  @override
  State<DiceRoll> createState() => _DiceRollState();
}

class _DiceRollState extends State<DiceRoll>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 850),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          if (widget.onComplete != null) {
            widget.onComplete!();
          } else {
            Navigator.of(context).pop();
          }
        }
      });
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.value = 1;
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xf214242b),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xff79938e), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0xb3000000),
              blurRadius: 32,
              spreadRadius: 8,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final landed = t >= .65;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 2; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Transform.translate(
                            offset: Offset(
                              landed
                                  ? 0
                                  : (i == 0 ? -180 : 160) *
                                        math.pow(1 - t / .65, 3).toDouble(),
                              landed
                                  ? 0
                                  : 120 * math.pow(1 - t / .65, 3).toDouble() -
                                        48 *
                                            (1 - t / .65) *
                                            math
                                                .sin(t / .65 * math.pi * 3)
                                                .abs(),
                            ),
                            child: Transform.rotate(
                              angle: landed
                                  ? 0
                                  : (1 - t / .65) * math.pi * (i == 0 ? 4 : -4),
                              child: CustomPaint(
                                size: const Size(64, 64),
                                painter: _DiePainter(
                                  landed
                                      ? (i == 0 ? widget.first : widget.second)
                                      : 1 + ((t * 30).floor() + i * 3) % 6,
                                  i == 0
                                      ? const Color(0xffefd6a3)
                                      : const Color(0xff70d8bf),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    landed
                        ? widget.first == 0
                              ? 'Awaiting the realm’s roll'
                              : '${widget.first} + ${widget.second} = ${widget.first + widget.second}'
                        : 'Rolling…',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _DiePainter extends CustomPainter {
  const _DiePainter(this.value, this.color);
  final int value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawShadow(
      Path()
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14))),
      Colors.black,
      8,
      true,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, .3)!, color],
        ).createShader(rect),
    );
    final pips = <Offset>[
      if (value.isOdd) const Offset(.5, .5),
      if (value >= 2) ...[const Offset(.25, .25), const Offset(.75, .75)],
      if (value >= 4) ...[const Offset(.75, .25), const Offset(.25, .75)],
      if (value == 6) ...[const Offset(.25, .5), const Offset(.75, .5)],
    ];
    for (final pip in pips) {
      canvas.drawCircle(
        Offset(pip.dx * size.width, pip.dy * size.height),
        size.width * .065,
        Paint()..color = const Color(0xff14242b),
      );
    }
  }

  @override
  bool shouldRepaint(_DiePainter oldDelegate) =>
      value != oldDelegate.value || color != oldDelegate.color;
}
