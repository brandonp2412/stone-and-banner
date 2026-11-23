import 'package:flutter/material.dart';

import 'game_colors.dart';

import '../engine/board.dart';
import '../engine/match.dart';

/// Animate only goods actually credited by the reducer, including bank limits.
class ResourceHarvest extends StatefulWidget {
  const ResourceHarvest({
    super.key,
    required this.state,
    required this.seat,
    required this.anchors,
    this.deferAnimation = false,
  });
  final bool deferAnimation;
  final Map<Resource, LayerLink> anchors;
  final MatchState state;
  final int seat;

  @override
  State<ResourceHarvest> createState() => _ResourceHarvestState();
}

class _ResourceHarvestState extends State<ResourceHarvest>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4100),
    value: 1,
  );
  Map<Resource, int> _gains = {};

  @override
  void didUpdateWidget(covariant ResourceHarvest oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deferAnimation &&
        !widget.deferAnimation &&
        _gains.isNotEmpty &&
        !MediaQuery.disableAnimationsOf(context)) {
      _motion.forward(from: 0);
    }
    if (widget.state.rollCount <= oldWidget.state.rollCount ||
        widget.seat != oldWidget.seat) {
      return;
    }
    _gains = {
      for (final good in Resource.values)
        if ((widget.state.players[widget.seat].stores[good] ?? 0) >
            (oldWidget.state.players[widget.seat].stores[good] ?? 0))
          good:
              (widget.state.players[widget.seat].stores[good] ?? 0) -
              (oldWidget.state.players[widget.seat].stores[good] ?? 0),
    };
    _motion.value = 1;
    if (_gains.isNotEmpty &&
        !widget.deferAnimation &&
        !MediaQuery.disableAnimationsOf(context)) {
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
    child: LayoutBuilder(
      builder: (context, bounds) => AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          final t = _motion.value;
          if (t >= 1) return const SizedBox.shrink();
          return Stack(
            children: [
              for (final entry in _gains.entries)
                Positioned(
                  left: 0,
                  top: 0,
                  child: CompositedTransformFollower(
                    link: widget.anchors[entry.key]!,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.topCenter,
                    followerAnchor: Alignment.bottomCenter,
                    offset: const Offset(0, -12),
                    child: Opacity(
                      opacity: t < .06
                          ? (t / .06).clamp(0.0, 1.0)
                          : t > .88
                          ? ((1 - t) / .12).clamp(0.0, 1.0)
                          : 1,
                      child: Container(
                        key: ValueKey('resource-gain-${entry.key.name}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: gameColor(context, const Color(0xff294c43)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: gameColor(context, const Color(0xff70d8bf)),
                          ),
                        ),
                        child: Text(
                          '+${entry.value} ${entry.key.name}',
                          style: TextStyle(
                            color: gameColor(context, const Color(0xffeafff5)),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// Celebrate gains on the inventory tile that received them.
class ResourceRewardPulse extends StatefulWidget {
  const ResourceRewardPulse({
    super.key,
    this.anchor,
    this.deferAnimation = false,
    required this.count,
    required this.seat,
    required this.color,
    required this.child,
  });

  final bool deferAnimation;
  final LayerLink? anchor;
  final int count;
  final int seat;
  final Color color;
  final Widget child;

  @override
  State<ResourceRewardPulse> createState() => _ResourceRewardPulseState();
}

class _ResourceRewardPulseState extends State<ResourceRewardPulse>
    with SingleTickerProviderStateMixin {
  bool _pendingGain = false;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant ResourceRewardPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seat != oldWidget.seat ||
        MediaQuery.disableAnimationsOf(context)) {
      _pendingGain = false;
      _motion.value = 1;
    } else {
      if (widget.count > oldWidget.count) _pendingGain = true;
      if (widget.deferAnimation) {
        _motion.value = 1;
      } else if (_pendingGain) {
        _pendingGain = false;
        _motion.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: widget.anchor == null
        ? widget.child
        : CompositedTransformTarget(link: widget.anchor!, child: widget.child),
    builder: (context, child) {
      final t = _motion.value;
      final pulse = t < .2
          ? Curves.easeOut.transform(t / .2)
          : 1 - Curves.easeInOut.transform((t - .2) / .8);
      return Transform.translate(
        offset: Offset(0, -5 * pulse),
        child: Transform.scale(
          scale: 1 + .1 * pulse,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: .65 * pulse),
                  blurRadius: 14 * pulse,
                  spreadRadius: 2 * pulse,
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    },
  );
}
