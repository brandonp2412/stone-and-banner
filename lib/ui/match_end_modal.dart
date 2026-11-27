import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_colors.dart';

import '../engine/match.dart';

/// Full-screen, non-dismissible result ceremony. Pure presentation: no match
/// events, rewards or replay state are changed when it appears or closes.
class MatchEndModal extends StatefulWidget {
  const MatchEndModal({
    super.key,
    required this.state,
    required this.winner,
    required this.victory,
    required this.onReview,
    this.onHome,
    this.onPlayAgain,
  });

  final MatchState state;
  final int winner;
  final bool victory;
  final VoidCallback onReview;
  final VoidCallback? onHome;
  final VoidCallback? onPlayAgain;

  @override
  State<MatchEndModal> createState() => _MatchEndModalState();
}

class _MatchEndModalState extends State<MatchEndModal>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _celebration;

  static const gold = Color(0xfff4ce80);
  static const dusk = Color(0xffcba4f6);

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _celebration = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4700),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
      _celebration.value = .3;
    } else {
      if (!_entrance.isAnimating && _entrance.value == 0) _entrance.forward();
      if (!_celebration.isAnimating) _celebration.repeat();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _celebration.dispose();
    super.dispose();
  }

  Widget _playAgainButton(Color accent, bool compact) => FilledButton.icon(
    key: const ValueKey('match-finale-play-again'),
    onPressed: widget.onPlayAgain,
    icon: const Icon(Icons.replay_rounded, size: 18),
    label: const Text('Play again'),
    style: FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: gameColor(context, const Color(0xff17242b)),
      minimumSize: Size.fromHeight(compact ? 35 : 44),
      padding: const EdgeInsets.symmetric(horizontal: 9),
    ),
  );

  /// Portrait results use the phone's height instead of squeezing the
  /// landscape trophy, scores, and actions into side-by-side columns.
  Widget _portraitContent(Color accent, String winnerName, int points) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('match-finale-portrait-scroll'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'STONE & BANNER  /  MATCH COMPLETE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.25,
                      fontWeight: FontWeight.w700,
                      color: gameColor(context, const Color(0xffb5c9c8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent.withValues(alpha: .6),
                          width: 2,
                        ),
                        gradient: RadialGradient(
                          colors: [
                            accent.withValues(alpha: .24),
                            accent.withValues(alpha: .02),
                          ],
                        ),
                      ),
                      child: Icon(
                        widget.victory
                            ? Icons.emoji_events_rounded
                            : Icons.shield_moon_rounded,
                        size: 64,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.victory ? 'VICTORY' : 'DEFEAT',
                    key: const ValueKey('match-finale-outcome'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      height: 1.1,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$winnerName claims the realm',
                    key: const ValueKey('match-finale-winner'),
                    textAlign: TextAlign.center,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: gameColor(context, Colors.white),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$points / 15 Renown  ·  Round ${widget.state.round}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: gameColor(context, const Color(0xffb5c9c8)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (
                    var index = 0;
                    index < widget.state.players.length;
                    index++
                  )
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: index == widget.winner
                              ? accent.withValues(alpha: .15)
                              : gameColor(context, const Color(0x9920313a)),
                          border: Border.all(
                            color: index == widget.winner
                                ? accent
                                : gameColor(context, const Color(0xff45616a)),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            if (index == widget.winner) ...[
                              Icon(
                                Icons.workspace_premium_rounded,
                                size: 20,
                                color: accent,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                widget.state.players[index].id,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${MatchEngine.score(widget.state, index)} / 15',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: index == widget.winner
                                    ? accent
                                    : gameColor(
                                        context,
                                        const Color(0xffafc6c8),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    widget.victory ? 'THE CROWN IS YOURS' : 'A REALM FALLS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: accent,
                      letterSpacing: 1.4,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (widget.onPlayAgain != null) ...[
            _playAgainButton(accent, false),
            const SizedBox(height: 6),
          ],
          FilledButton.icon(
            key: const ValueKey('match-finale-review'),
            onPressed: widget.onReview,
            icon: const Icon(Icons.map_outlined, size: 20),
            label: const Text('View board'),
            style: FilledButton.styleFrom(
              backgroundColor: widget.onPlayAgain == null
                  ? accent
                  : gameColor(context, const Color(0xff243b43)),
              foregroundColor: widget.onPlayAgain == null
                  ? gameColor(context, const Color(0xff17242b))
                  : gameColor(context, const Color(0xffe4eff0)),
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          if (widget.onHome != null) ...[
            const SizedBox(height: 6),
            FilledButton.tonalIcon(
              key: const ValueKey('match-finale-home'),
              onPressed: widget.onHome,
              icon: const Icon(Icons.home_rounded, size: 20),
              label: const Text('Home'),
              style: FilledButton.styleFrom(
                backgroundColor: gameColor(context, const Color(0xff243b43)),
                foregroundColor: gameColor(context, const Color(0xffe4eff0)),
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = gameColor(context, widget.victory ? gold : dusk);
    final winnerName = widget.state.players[widget.winner].id;
    final points = MatchEngine.score(widget.state, widget.winner);
    final available = MediaQuery.sizeOf(context);
    final portrait =
        available.height > available.width && available.width < 700;
    final compact = available.height < 355;
    final height = portrait
        ? math.min(available.height * .76, available.height - 28)
        : math.min(
            (compact ? 283.0 : 310.0) + (widget.onPlayAgain != null ? 45 : 0),
            available.height - 22,
          );
    return Stack(
      children: [
        ModalBarrier(
          key: ValueKey('match-finale-barrier'),
          color: gameColor(context, const Color(0xd90a131a)),
          dismissible: false,
        ),
        Center(
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) {
              final t = Curves.easeOutBack.transform(_entrance.value);
              return Opacity(
                opacity: _entrance.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 24 * (1 - _entrance.value)),
                  child: Transform.scale(scale: .86 + .14 * t, child: child),
                ),
              );
            },
            child: Dialog(
              key: const ValueKey('match-finale-dialog'),
              insetPadding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: Colors.transparent,
              shadowColor: Colors.black87,
              elevation: 20,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: portrait ? 440 : 620,
                  maxHeight: height,
                ),
                child: Semantics(
                  label:
                      '${widget.victory ? 'Victory' : 'Defeat'}. '
                      '$winnerName wins with $points renown.',
                  explicitChildNodes: true,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(-.65, -.25),
                              radius: 1.4,
                              colors: widget.victory
                                  ? [
                                      gameColor(
                                        context,
                                        const Color(0xff315248),
                                      ),
                                      gameColor(
                                        context,
                                        const Color(0xff192e38),
                                      ),
                                      gameColor(
                                        context,
                                        const Color(0xff101d29),
                                      ),
                                    ]
                                  : [
                                      gameColor(
                                        context,
                                        const Color(0xff3b304e),
                                      ),
                                      gameColor(
                                        context,
                                        const Color(0xff202b3c),
                                      ),
                                      gameColor(
                                        context,
                                        const Color(0xff111d2c),
                                      ),
                                    ],
                            ),
                            border: Border.all(
                              color: accent.withValues(alpha: .6),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _celebration,
                            builder: (context, _) => CustomPaint(
                              painter: _FinaleParticles(
                                progress: _celebration.value,
                                accent: accent,
                                celebrating: widget.victory,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (portrait)
                        _portraitContent(accent, winnerName, points)
                      else
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 16 : 23,
                            vertical: compact ? 8 : 18,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: compact ? 116 : 151,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: AnimatedBuilder(
                                        animation: _celebration,
                                        builder: (context, child) =>
                                            Transform.translate(
                                              offset: Offset(
                                                0,
                                                math.sin(
                                                      _celebration.value *
                                                          math.pi *
                                                          2,
                                                    ) *
                                                    4,
                                              ),
                                              child: child,
                                            ),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Container(
                                              width: compact ? 103 : 134,
                                              height: compact ? 103 : 134,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: accent.withValues(
                                                    alpha: .5,
                                                  ),
                                                  width: 2,
                                                ),
                                                gradient: RadialGradient(
                                                  colors: [
                                                    accent.withValues(
                                                      alpha: .18,
                                                    ),
                                                    accent.withValues(
                                                      alpha: .02,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              widget.victory
                                                  ? Icons.emoji_events_rounded
                                                  : Icons.shield_moon_rounded,
                                              size: compact ? 70 : 91,
                                              color: accent,
                                              shadows: [
                                                Shadow(
                                                  color: accent.withValues(
                                                    alpha: .5,
                                                  ),
                                                  blurRadius: 28,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.victory
                                          ? compact
                                                ? 'YOUR CROWN'
                                                : 'THE CROWN IS YOURS'
                                          : compact
                                          ? 'REALM LOST'
                                          : 'A REALM FALLS',
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        letterSpacing: 1.15,
                                        fontWeight: FontWeight.w800,
                                        fontSize: compact ? 8 : 9,
                                        color: accent,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                  ],
                                ),
                              ),
                              SizedBox(width: compact ? 13 : 22),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'STONE & BANNER  /  MATCH COMPLETE',
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: gameColor(
                                          context,
                                          const Color(0xffaebfc0),
                                        ),
                                        letterSpacing: 1.3,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        widget.victory ? 'VICTORY' : 'DEFEAT',
                                        key: const ValueKey(
                                          'match-finale-outcome',
                                        ),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: compact ? 32 : 49,
                                          letterSpacing: 2,
                                          height: 1,
                                          color: accent,
                                          shadows: [
                                            Shadow(
                                              color: accent.withValues(
                                                alpha: .3,
                                              ),
                                              blurRadius: 15,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$winnerName claims the realm',
                                      key: const ValueKey(
                                        'match-finale-winner',
                                      ),
                                      maxLines: 2,
                                      softWrap: true,
                                      overflow: TextOverflow.visible,
                                      style: TextStyle(
                                        fontSize: compact ? 13 : 16,
                                        fontWeight: FontWeight.w700,
                                        color: gameColor(context, Colors.white),
                                      ),
                                    ),
                                    Text(
                                      '$points / 15 Renown  ·  Round ${widget.state.round}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: gameColor(
                                          context,
                                          const Color(0xffb5c9c8),
                                        ),
                                      ),
                                      maxLines: 1,
                                    ),
                                    SizedBox(height: compact ? 6 : 10),
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, box) => SingleChildScrollView(
                                          child: Wrap(
                                            spacing: 6,
                                            runSpacing: 5,
                                            children: [
                                              for (
                                                var index = 0;
                                                index <
                                                    widget.state.players.length;
                                                index++
                                              )
                                                Builder(
                                                  builder: (context) {
                                                    final score =
                                                        MatchEngine.score(
                                                          widget.state,
                                                          index,
                                                        );
                                                    final leading =
                                                        index == widget.winner;
                                                    return Container(
                                                      width:
                                                          (box.maxWidth - 6) /
                                                          2,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 9,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: leading
                                                            ? accent.withValues(
                                                                alpha: .16,
                                                              )
                                                            : gameColor(
                                                                context,
                                                                const Color(
                                                                  0x9920313a,
                                                                ),
                                                              ),
                                                        border: Border.all(
                                                          color: leading
                                                              ? accent
                                                              : gameColor(
                                                                  context,
                                                                  const Color(
                                                                    0xff45616a,
                                                                  ),
                                                                ),
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              9,
                                                            ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          if (leading) ...[
                                                            Icon(
                                                              Icons
                                                                  .workspace_premium_rounded,
                                                              size: 14,
                                                              color: accent,
                                                            ),
                                                            const SizedBox(
                                                              width: 3,
                                                            ),
                                                          ],
                                                          Expanded(
                                                            child: Text(
                                                              widget
                                                                  .state
                                                                  .players[index]
                                                                  .id,
                                                              maxLines: 2,
                                                              softWrap: true,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: gameColor(
                                                                  context,
                                                                  Colors.white,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 5,
                                                          ),
                                                          Text(
                                                            '$score',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              color: leading
                                                                  ? accent
                                                                  : gameColor(
                                                                      context,
                                                                      const Color(
                                                                        0xffafc6c8,
                                                                      ),
                                                                    ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (widget.onPlayAgain != null) ...[
                                      _playAgainButton(accent, compact),
                                      const SizedBox(height: 4),
                                    ],
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.icon(
                                            key: const ValueKey(
                                              'match-finale-review',
                                            ),
                                            onPressed: widget.onReview,
                                            icon: const Icon(
                                              Icons.map_outlined,
                                              size: 18,
                                            ),
                                            label: const Text('View board'),
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  widget.onPlayAgain == null
                                                  ? accent
                                                  : gameColor(
                                                      context,
                                                      const Color(0xff243b43),
                                                    ),
                                              foregroundColor: gameColor(
                                                context,
                                                widget.onPlayAgain == null
                                                    ? const Color(0xff17242b)
                                                    : const Color(0xffe4eff0),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 9,
                                                  ),
                                              minimumSize: Size.fromHeight(
                                                compact ? 35 : 43,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (widget.onHome != null) ...[
                                          const SizedBox(width: 8),
                                          FilledButton.tonalIcon(
                                            key: const ValueKey(
                                              'match-finale-home',
                                            ),
                                            onPressed: widget.onHome,
                                            icon: const Icon(
                                              Icons.home_rounded,
                                              size: 18,
                                            ),
                                            label: const Text('Home'),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: gameColor(
                                                context,
                                                const Color(0xff243b43),
                                              ),
                                              foregroundColor: gameColor(
                                                context,
                                                const Color(0xffe4eff0),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                side: BorderSide(
                                                  color: gameColor(
                                                    context,
                                                    const Color(0xff6b939a),
                                                  ),
                                                ),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                  ),
                                              minimumSize: Size(
                                                0,
                                                compact ? 35 : 43,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
    );
  }
}

class _FinaleParticles extends CustomPainter {
  const _FinaleParticles({
    required this.progress,
    required this.accent,
    required this.celebrating,
  });
  final double progress;
  final Color accent;
  final bool celebrating;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < (celebrating ? 40 : 23); i++) {
      final fraction = (i * .61803398875) % 1.0;
      final stagger = (i * .1733) % 1.0;
      final y = ((progress + stagger) % 1.0) * size.height;
      final x =
          (fraction * size.width +
                  math.sin((progress * 2 + i * .33) * math.pi) * 9)
              .clamp(0.0, size.width);
      final opacity = math.sin(y / size.height * math.pi).abs() * .56;
      final paint = Paint()
        ..color = (i % 3 == 0 ? const Color(0xffffffff) : accent).withValues(
          alpha: opacity,
        );
      if (celebrating) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(progress * 5 + i);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: i % 4 == 0 ? 3 : 2,
              height: i % 4 == 0 ? 11 : 7,
            ),
            const Radius.circular(1),
          ),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(Offset(x, y), i % 4 == 0 ? 2.8 : 1.4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FinaleParticles oldDelegate) =>
      progress != oldDelegate.progress ||
      accent != oldDelegate.accent ||
      celebrating != oldDelegate.celebrating;
}
