import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Presentation only: the caller supplies the engine's saved dice result.
class DiceRoll extends StatefulWidget {
  const DiceRoll({super.key, required this.first, required this.second});

  final int first;
  final int second;

  @override
  State<DiceRoll> createState() => _DiceRollState();
}

class _DiceRollState extends State<DiceRoll>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          Navigator.of(context).pop();
        }
      });
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
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
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      backgroundColor: const Color(0xff14242b),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final landed = t >= .65;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  landed ? 'The dice have spoken' : 'Rolling dice…',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 28),
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 2; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              landed
                                  ? 0
                                  : -24 *
                                        (1 - t) *
                                        math.sin(t * math.pi * 7 + i).abs(),
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
                    style: Theme.of(context).textTheme.headlineSmall,
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
