import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A contextual explanation that leaves the surrounding layout in place.
class FocusHint extends StatefulWidget {
  const FocusHint({
    super.key,
    required this.target,
    required this.onOpen,
    required this.onDismiss,
    required this.title,
    required this.explanation,
    this.actionLabel = 'Got it',
  });
  final String title, explanation, actionLabel;
  final GlobalKey target;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  State<FocusHint> createState() => _FocusHintState();
}

class _FocusHintState extends State<FocusHint> {
  Rect? _target;

  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = widget.target.currentContext?.findRenderObject();
      final overlay = context.findRenderObject();
      if (target is! RenderBox || overlay is! RenderBox || !target.hasSize) {
        return;
      }
      final rect =
          (target.localToGlobal(Offset.zero, ancestor: overlay) & target.size)
              .inflate(5);
      if (rect != _target) setState(() => _target = rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    return LayoutBuilder(
      builder: (context, bounds) {
        final padding = MediaQuery.paddingOf(context);
        final target = _target;
        final landscape =
            bounds.maxHeight < 500 ||
            (target != null && target.height > bounds.maxHeight / 2);
        final width = math.min(landscape ? 288.0 : 340.0, bounds.maxWidth - 32);
        final above = target != null && target.center.dy > bounds.maxHeight / 2;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target == null ? 0 : 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          builder: (context, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  child: CustomPaint(painter: _FocusPainter(target)),
                ),
              ),
              if (target != null)
                Positioned.fromRect(
                  rect: target,
                  child: Semantics(
                    label: widget.actionLabel,
                    button: true,
                    child: GestureDetector(
                      onTap: widget.onOpen,
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              Positioned(
                left: target == null
                    ? 16
                    : (landscape
                              ? target.right + 16
                              : target.center.dx - width / 2)
                          .clamp(16.0, bounds.maxWidth - width - 16),
                width: width,
                top: landscape
                    ? padding.top + 16
                    : above
                    ? null
                    : math.max(padding.top + 16, (target?.bottom ?? 70) + 16),
                bottom: landscape
                    ? null
                    : above
                    ? math.max(
                        padding.bottom + 16,
                        bounds.maxHeight - target.top + 16,
                      )
                    : null,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(
                      100,
                      landscape
                          ? bounds.maxHeight - padding.vertical - 32
                          : above
                          ? target.top - padding.top - 32
                          : bounds.maxHeight -
                                (target?.bottom ?? 70) -
                                padding.bottom -
                                32,
                    ),
                  ),
                  child: Material(
                    elevation: 12,
                    color: const Color(0xff20363e),
                    borderRadius: BorderRadius.circular(16),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xffefd6a3),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Dismiss hint',
                                  onPressed: widget.onDismiss,
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                              ],
                            ),
                            Text(
                              widget.explanation,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: Color(0xffdce8e9),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: widget.onOpen,
                                child: Text(widget.actionLabel),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FocusPainter extends CustomPainter {
  _FocusPainter(this.target);
  final Rect? target;
  @override
  void paint(Canvas canvas, Size size) {
    final backdrop = Path()..addRect(Offset.zero & size);
    if (target == null) return;
    final focus = RRect.fromRectAndRadius(target!, const Radius.circular(10));
    final hole = Path()..addRRect(focus);
    canvas.drawPath(
      Path.combine(PathOperation.difference, backdrop, hole),
      Paint()..color = const Color(0xb8101e25),
    );
    canvas.drawRRect(
      focus,
      Paint()
        ..color = const Color(0xffefd6a3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FocusPainter oldDelegate) => oldDelegate.target != target;
}
