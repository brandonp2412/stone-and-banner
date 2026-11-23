import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/match.dart';

/// Spark, shockwave and floating icon effects drawn over the real map.
///
/// Deliberately separate from match rules: playback, LAN state and saves are
/// unaffected, and each new committed event restarts a short animation.
class BoardEventEffects extends StatefulWidget {
  const BoardEventEffects({
    super.key,
    required this.eventIndex,
    required this.event,
    required this.anchor,
  });

  final int eventIndex;
  final MatchEvent? event;
  final Offset anchor;

  @override
  State<BoardEventEffects> createState() => _BoardEventEffectsState();
}

class _BoardEventEffectsState extends State<BoardEventEffects>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant BoardEventEffects oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.eventIndex > oldWidget.eventIndex && widget.event != null) {
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _EventBurstPainter(
          event: widget.event,
          anchor: widget.anchor,
          progress: _motion,
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _EventBurstPainter extends CustomPainter {
  _EventBurstPainter({
    required this.event,
    required this.anchor,
    required this.progress,
  }) : super(repaint: progress);

  final MatchEvent? event;
  final Offset anchor;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final event = this.event;
    final t = progress.value;
    if (event == null || t >= 1) return;
    // Dice now activate their matching production tokens directly. Unplaced
    // economic/turn events must not produce a misleading centre-map burst.
    if (event is RollDice ||
        event is EndTurn ||
        event is BankExchange ||
        event is ProposeTrade ||
        event is RespondTrade ||
        event is WithdrawTrade ||
        event is DevelopTown) {
      return;
    }
    final invasion = event is ResolveInvasion;
    final theft = event is MoveBandit;
    final construction =
        event is PlaceRoad ||
        event is PlaceVillage ||
        event is UpgradeSite ||
        event is FortifyTown;
    final combat =
        invasion ||
        theft ||
        event is RecruitGuard ||
        event is MoveGuard ||
        event is PlayStrategyCard;
    final color = invasion
        ? const Color(0xffff7656)
        : theft
        ? const Color(0xffffa783)
        : construction
        ? const Color(0xff75ecc4)
        : combat
        ? const Color(0xffc5adff)
        : const Color(0xfff3cf88);
    final glyph = invasion
        ? '🔥'
        : theft
        ? '🦹'
        : event is RollDice
        ? '🎲'
        : construction
        ? '✨'
        : combat
        ? '⚔️'
        : '✦';
    final center = Offset(
      anchor.dx.clamp(0.0, size.width),
      anchor.dy.clamp(0.0, size.height),
    );
    final fade = (1 - t).clamp(0.0, 1.0);
    final impulse = Curves.easeOutCubic.transform(t);
    final ringCount = invasion
        ? 4
        : theft
        ? 3
        : 2;
    for (var ring = 0; ring < ringCount; ring++) {
      final stagger = ((t - ring * .095) / (1 - ring * .095)).clamp(0.0, 1.0);
      if (t < ring * .095) continue;
      final radius = (invasion ? 38 : 16) + (invasion ? 200 : 72) * stagger;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (4.5 - stagger * 3.5).clamp(1.0, 4.5)
          ..color = color.withValues(alpha: (.65 * (1 - stagger)).clamp(0, 1)),
      );
    }
    final sparkCount = invasion
        ? 18
        : theft
        ? 12
        : 9;
    for (var i = 0; i < sparkCount; i++) {
      final angle = i * 2 * math.pi / sparkCount + (invasion ? t * .3 : 0);
      final distance = (invasion ? 135 : 64) * impulse;
      final position =
          center +
          Offset(math.cos(angle), math.sin(angle)) * distance +
          Offset(0, -12 * t);
      final size = (invasion ? 6.5 : 4.5) * fade + 1;
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(angle + t * math.pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: size, height: size * 1.7),
          const Radius.circular(2),
        ),
        Paint()..color = color.withValues(alpha: fade),
      );
      canvas.restore();
    }
    final text = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontSize: invasion ? 54 : 37,
          color: color.withValues(alpha: fade),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.saveLayer(
      null,
      Paint()..color = Colors.white.withValues(alpha: fade),
    );
    text.paint(
      canvas,
      center - Offset(text.width / 2, text.height / 2 + 30 * impulse),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EventBurstPainter oldDelegate) =>
      event != oldDelegate.event || anchor != oldDelegate.anchor;
}
