import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/match.dart';
import 'trade_feedback.dart';

/// Presentation-only feedback: every cue is derived from a committed event.
/// No animation enters the reducer, replay, random seed, or network protocol.
class MatchActivity extends StatefulWidget {
  const MatchActivity({
    super.key,
    required this.state,
    required this.viewerSeat,
    this.computerSeats = const <int>{},
  });

  final MatchState state;
  final int viewerSeat;
  final Set<int> computerSeats;

  @override
  State<MatchActivity> createState() => _MatchActivityState();
}

class _ActivityCue {
  const _ActivityCue({
    required this.index,
    required this.emoji,
    required this.title,
    required this.detail,
    required this.color,
    this.cheeky = false,
  });

  final int index;
  final String emoji, title, detail;
  final Color color;
  final bool cheeky;
}

class _MatchActivityState extends State<MatchActivity> {
  _ActivityCue? _cue;
  Timer? _dismiss;

  @override
  void didUpdateWidget(covariant MatchActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    final state = widget.state;
    if (state.events.length <= oldWidget.state.events.length) return;
    final event = state.events.last;
    final actor = event is RespondTactical
        ? event.player
        : event is RespondTrade
        ? event.player
        : oldWidget.state.active;
    final cue = _describe(state, event, actor);
    if (cue == null) return;
    _dismiss?.cancel();
    setState(() => _cue = cue);
    _dismiss = Timer(
      Duration(
        milliseconds: event is ProposeTrade || event is RespondTrade
            ? 5000
            : 2200,
      ),
      () {
        if (mounted) setState(() => _cue = null);
      },
    );
  }

  _ActivityCue? _describe(MatchState state, MatchEvent event, int actor) {
    final index = state.events.length;
    final isAi = widget.computerSeats.contains(actor);
    final player = state.players[actor].id;
    final prefix = isAi ? player : player;
    const gold = Color(0xffeac587);
    const teal = Color(0xff67dbbf);
    const coral = Color(0xffffa28e);
    const blue = Color(0xffa7c8ff);
    const violet = Color(0xffd1b2f5);

    _ActivityCue cue(
      String emoji,
      String title,
      String detail, {
      Color color = gold,
      bool cheeky = false,
    }) => _ActivityCue(
      index: index,
      emoji: cheeky ? '😈' : emoji,
      title: title,
      detail: detail,
      color: color,
      cheeky: cheeky,
    );

    switch (event) {
      case RollDice():
        return cue('🎲', '$prefix rolls the dice', '', color: blue);
      case PlaceVillage():
        return cue(
          '🏘️',
          '$prefix settles new land',
          'A village rises',
          color: teal,
        );
      case PlaceRoad():
        return cue(
          '🛤️',
          '$prefix lays a road',
          'The realm grows',
          color: teal,
        );
      case UpgradeSite():
        return cue(
          '🏰',
          '$prefix upgrades a settlement',
          'Stone upon stone',
          color: teal,
        );
      case DevelopTown():
        return cue(
          '📜',
          '$prefix develops a town',
          'A little more power',
          color: violet,
        );
      case FortifyTown():
        return cue(
          '🛡️',
          '$prefix fortifies a town',
          'Walls stand ready',
          color: teal,
        );
      case RecruitKnight():
        return cue(
          '⚔️',
          '$prefix recruits a knight',
          'A new sword joins the realm',
          color: blue,
        );
      case ActivateKnight():
        return cue(
          '✨',
          '$prefix activates a knight',
          'Ready for trouble',
          color: blue,
        );
      case PromoteKnight():
        return cue(
          '🌟',
          '$prefix promotes a knight',
          'A mighty warrior emerges',
          color: gold,
        );
      case MoveKnight():
        return cue(
          '🐎',
          '$prefix moves a knight',
          'Hooves on the march',
          color: blue,
        );
      case MoveBandit():
        final victim = event.victim;
        final targeted = isAi && victim == widget.viewerSeat;
        return cue(
          '🦹',
          targeted ? '$player eyes your goods!' : '$prefix moves the bandit',
          victim == null
              ? 'The bandit prowls a new hex'
              : 'A raid on ${state.players[victim].id} — can they stop it?',
          color: coral,
          cheeky: targeted,
        );
      case RespondTactical():
        if (event.choice == TacticalChoice.intercept) {
          return cue(
            '🛡️',
            '$prefix blocks a robbery',
            'Knight to the rescue',
            color: teal,
          );
        }
        if (event.choice == TacticalChoice.counter) {
          return cue(
            '🃏',
            '$prefix plays a counter',
            'Nice try!',
            color: violet,
          );
        }
        if (event.choice == TacticalChoice.aid) {
          return cue(
            '🤝',
            '$prefix sends reinforcements',
            'Every defender counts',
            color: teal,
          );
        }
        return cue(
          '🎭',
          '$prefix makes a choice',
          'The story continues',
          color: blue,
        );
      case TimeoutTactical():
        return cue(
          '⌛',
          'Response window closes',
          'The realm moves on',
          color: coral,
        );
      case ResolveInvasion():
        return cue(
          '🔥',
          'Barbarian assault!',
          state.lastInvasion,
          color: coral,
        );
      case BankExchange():
        return cue(
          '🪙',
          '$prefix visits the market',
          'A trade with the bank',
          color: gold,
        );
      case ProposeTrade():
        if (actor != widget.viewerSeat && event.target != widget.viewerSeat) {
          return null;
        }
        return cue(
          '🤝',
          '$prefix sends an offer',
          '${event.giveCount} ${event.give.name} for ${event.wantCount} ${event.want.name}',
          color: violet,
        );
      case RespondTrade():
        final message = tradeFeedbackForResponse(
          state,
          event,
          viewer: widget.viewerSeat,
        );
        if (message == null) return null;
        final cheeky =
            isAi &&
            !event.accept &&
            tradeProposerForEvent(state, event.offerId ?? -1) ==
                widget.viewerSeat;
        return cue(
          event.accept ? '🎉' : '📨',
          event.accept ? 'Deal sealed!' : 'Offer declined',
          message,
          color: event.accept ? teal : coral,
          cheeky: cheeky,
        );
      case WithdrawTrade():
        return cue(
          '📦',
          '$prefix withdraws an offer',
          'Reserved goods returned',
          color: violet,
        );
      case PlayStrategyCard():
        final target = event.target;
        final cheeky = isAi && target == widget.viewerSeat;
        return cue(
          '🃏',
          cheeky ? '$player has a trick for you' : '$prefix plays a card',
          cheeky ? 'An opponent makes a cheeky move' : 'A strategy unfolds',
          color: violet,
          cheeky: cheeky,
        );
      case DiscardStrategyCard():
        return cue(
          '🍂',
          '$prefix discards a card',
          'Making room for new plans',
          color: blue,
        );
      case EndTurn():
        return cue('👋', '$prefix ends their turn', '', color: blue);
    }
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        reverseDuration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -.55),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: _cue == null
            ? const SizedBox.shrink(key: ValueKey('activity-empty'))
            : _ActivityCard(key: ValueKey(_cue!.index), cue: _cue!),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({super.key, required this.cue});
  final _ActivityCue cue;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('match-activity-notice'),
    decoration: BoxDecoration(
      color: const Color(0xff172a33),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: cue.color.withValues(alpha: .65)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x9a000000),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 900 ? 8 : 15,
        vertical: MediaQuery.sizeOf(context).width < 900 ? 6 : 10,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey('bounce-${cue.index}'),
            tween: Tween(begin: .5, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: cue.cheeky
                ? Semantics(
                    label: 'Cheeky devil emoji',
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width < 900 ? 26 : 38,
                      height: MediaQuery.sizeOf(context).width < 900 ? 26 : 38,
                      child: CustomPaint(painter: _CheekyDevilPainter()),
                    ),
                  )
                : Text(
                    cue.emoji,
                    style: TextStyle(
                      fontSize: MediaQuery.sizeOf(context).width < 900
                          ? 22
                          : 32,
                    ),
                  ),
          ),
          SizedBox(width: MediaQuery.sizeOf(context).width < 900 ? 6 : 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cue.cheeky)
                  Text(
                    'CHEEKY MOVE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: cue.color,
                    ),
                  ),
                Text(
                  cue.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: MediaQuery.sizeOf(context).width < 900 ? 12 : 15,
                  ),
                ),
                if (cue.detail.isNotEmpty)
                  Text(
                    cue.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xffc7d8d9),
                      fontSize: MediaQuery.sizeOf(context).width < 900
                          ? 10
                          : 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Cross-platform, emoji-like mischievous devil: no platform emoji font needed.
class _CheekyDevilPainter extends CustomPainter {
  const _CheekyDevilPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 38, size.height / 38);
    const purple = Color(0xffb075ed);
    const deep = Color(0xff7845b7);
    final hornPaint = Paint()..color = deep;
    final leftHorn = Path()
      ..moveTo(5, 14)
      ..quadraticBezierTo(3, 6, 4, 0)
      ..quadraticBezierTo(10, 7, 14, 7)
      ..close();
    final rightHorn = Path()
      ..moveTo(24, 7)
      ..quadraticBezierTo(30, 6, 34, 0)
      ..quadraticBezierTo(35, 8, 32, 14)
      ..close();
    canvas.drawPath(leftHorn, hornPaint);
    canvas.drawPath(rightHorn, hornPaint);
    canvas.drawCircle(const Offset(19, 21), 16, Paint()..color = purple);
    canvas.drawCircle(
      const Offset(13.2, 18),
      3.5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(const Offset(25, 18), 3.5, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(14.4, 17.6),
      1.7,
      Paint()..color = const Color(0xff251833),
    );
    canvas.drawCircle(
      const Offset(26.2, 17.6),
      1.7,
      Paint()..color = const Color(0xff251833),
    );
    final brow = Paint()
      ..color = const Color(0xff512876)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(9, 12), const Offset(17, 13.7), brow);
    canvas.drawLine(const Offset(21, 13.7), const Offset(29, 12), brow);
    final smirk = Path()
      ..moveTo(10.5, 25)
      ..quadraticBezierTo(19, 33.7, 29, 23.5);
    canvas.drawPath(
      smirk,
      Paint()
        ..color = const Color(0xff43205b)
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      const Offset(30.2, 22.7),
      2,
      Paint()..color = const Color(0xffd9aaff),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CheekyDevilPainter oldDelegate) => false;
}
