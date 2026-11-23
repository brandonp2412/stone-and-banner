import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/board.dart';
import 'labels.dart';
import '../engine/match.dart';
import '../engine/cards.dart';
import '../engine/trade_sentiment.dart';
import 'trade_feedback.dart';
import 'emote_icon.dart';

/// Presentation-only feedback: every cue is derived from a committed event.
/// No animation enters the reducer, replay, random seed, or network protocol.
class MatchActivity extends StatefulWidget {
  const MatchActivity({
    super.key,
    required this.state,
    required this.viewerSeat,
    this.computerSeats = const <int>{},
    this.targetSeat,
    this.emotesOnly = false,
    this.showEmotes = true,
    this.emote,
    this.emoteSerial = 0,
    this.emoteSeat,
  });

  final MatchState state;
  final int viewerSeat;
  final Set<int> computerSeats;
  final int? targetSeat;
  final bool emotesOnly, showEmotes;
  final String? emote;
  final int emoteSerial;
  final int? emoteSeat;

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
    required this.seat,
    this.isEmote = false,
    this.cheeky = false,
  });

  final int index, seat;
  final bool isEmote;
  final String emoji, title, detail;
  final Color color;
  final bool cheeky;
}

class _MatchActivityState extends State<MatchActivity> {
  _ActivityCue? _cue;
  Timer? _dismiss;
  Timer? _reply;
  final _random = math.Random();

  void _showEmote(String emoji, int seat) {
    if (widget.targetSeat != null && widget.targetSeat != seat) return;
    _dismiss?.cancel();
    setState(
      () => _cue = _ActivityCue(
        index: -DateTime.now().microsecondsSinceEpoch,
        emoji: emoji,
        title: widget.state.players[seat].id,
        seat: seat,
        isEmote: true,
        detail: '',
        color: const Color(0xff67dbbf),
      ),
    );
    _dismiss = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _cue = null);
    });
  }

  @override
  void didUpdateWidget(covariant MatchActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showEmotes &&
        widget.emoteSerial != oldWidget.emoteSerial &&
        widget.emote != null) {
      _reply?.cancel();
      _showEmote(widget.emote!, widget.emoteSeat ?? widget.viewerSeat);
      // Bot replies are cosmetic and only belong to local reactions.
      final replies = widget.emoteSeat != null || widget.targetSeat != null
          ? <int>[]
          : widget.computerSeats
                .where(
                  (seat) =>
                      seat != widget.viewerSeat && _random.nextDouble() < .35,
                )
                .toList();
      if (replies.isNotEmpty) {
        final seat = replies[_random.nextInt(replies.length)];
        _reply = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) {
            _showEmote(widget.emote == '😤' ? '😏' : widget.emote!, seat);
          }
        });
      }
    }
    if (widget.emotesOnly) return;
    final state = widget.state;
    if (state.events.length <= oldWidget.state.events.length) return;
    final event = state.events.last;
    final actor = event is DiscardResources
        ? event.player
        : event is RespondTactical
        ? event.player
        : event is RespondTrade
        ? event.player
        : event is ProposeTrade && event.counterActor != null
        ? event.counterActor!
        : oldWidget.state.active;
    final cue =
        _tradeDeclineReaction(oldWidget.state, state, event) ??
        _cutOffReaction(oldWidget.state, state, event, actor) ??
        _describe(state, event, actor, oldWidget.state);
    if (cue == null ||
        (widget.targetSeat != null && cue.seat != widget.targetSeat)) {
      return;
    }
    _dismiss?.cancel();
    setState(() => _cue = cue);
    _dismiss = Timer(
      Duration(
        milliseconds: event is RespondTrade && event.accept
            ? 8000
            : event is ProposeTrade || event is RespondTrade
            ? 5000
            : 2200,
      ),
      () {
        if (mounted) setState(() => _cue = null);
      },
    );
  }

  _ActivityCue? _tradeDeclineReaction(
    MatchState before,
    MatchState after,
    MatchEvent event,
  ) {
    if (event is! RespondTrade ||
        event.accept ||
        event.player != widget.viewerSeat ||
        widget.computerSeats.contains(event.player) ||
        !TradeSentiment.angryAtDecline(after, after.events.length - 1)) {
      return null;
    }
    final offer = before.offers
        .where(
          (offer) =>
              offer.canRespond(event.player) &&
              (event.offerId == null || event.offerId == offer.id),
        )
        .firstOrNull;
    if (offer == null || !widget.computerSeats.contains(offer.proposer)) {
      return null;
    }
    return _ActivityCue(
      index: after.events.length,
      emoji: '😤',
      seat: offer.proposer,
      title: '${after.players[offer.proposer].id}: Fine, keep your goods!',
      detail: 'They’ll offer you fewer trades from now on.',
      color: const Color(0xffffa28e),
    );
  }

  _ActivityCue? _cutOffReaction(
    MatchState before,
    MatchState after,
    MatchEvent event,
    int actor,
  ) {
    final vertex = switch (event) {
      PlaceVillage() => event.vertex,
      RecruitGuard() => event.vertex,
      MoveGuard() => event.to,
      PlaceRoad() =>
        [
              before.topology.edges[event.edge].a,
              before.topology.edges[event.edge].b,
            ]
            .where(
              (v) => before.topology.vertices[v].edges.any(
                (e) => before.roads[e] != null && before.roads[e] != actor,
              ),
            )
            .firstOrNull,
      _ => null,
    };
    if (vertex == null || before.sites.containsKey(vertex)) {
      return null;
    }
    final junction = before.topology.vertices[vertex];
    final cutOff = List.generate(before.players.length, (i) => i).where((seat) {
      if (seat == actor) return false;
      // Occupying a road endpoint denies expansion; a junction also splits
      // the road even when a different route preserves its crown-road score.
      return junction.edges.any((edge) => before.roads[edge] == seat);
    }).toList()..sort();
    if (cutOff.isEmpty) return null;
    if (widget.computerSeats.contains(actor)) {
      return _ActivityCue(
        index: after.events.length,
        emoji: '😏',
        seat: actor,
        title: '${after.players[actor].id}: Beat you to it!',
        detail: 'That route is mine.',
        color: const Color(0xffffd449),
        cheeky: true,
      );
    }
    cutOff.removeWhere((seat) => !widget.computerSeats.contains(seat));
    if (cutOff.isEmpty) return null;
    final names = cutOff.map((seat) => after.players[seat].id).join(' & ');
    return _ActivityCue(
      index: after.events.length,
      emoji: '😤',
      seat: cutOff.first,
      title: '$names: Hey! You cut me off!',
      detail:
          'Your move blocks ${cutOff.length == 1 ? "their route" : "their routes"}',
      color: const Color(0xffffa28e),
    );
  }

  _ActivityCue? _describe(
    MatchState state,
    MatchEvent event,
    int actor,
    MatchState previous,
  ) {
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
      seat: actor,
      emoji: cheeky ? '😏' : emoji,
      title: title,
      detail: detail,
      color: color,
      cheeky: cheeky,
    );

    switch (event) {
      case DiscardResources():
        if (event.player == widget.viewerSeat) return null;
        final name = state.players[event.player].id;
        final jokes = [
          '$name just paid the bandit tax. Embarrassing.',
          '$name got mugged by basic arithmetic.',
          '$name donated to the Bad Decisions Fund.',
          '$name’s pockets have officially surrendered.',
        ];
        return cue(
          '📦',
          jokes[index % jokes.length],
          '${event.goods.values.fold<int>(0, (a, b) => a + b)} resources gone. Absolutely tragic.',
          color: blue,
        );
      // Ordinary moves already animate on the board; no duplicate pop-up.
      case RollDice():
        final newlyRelieved = state.reliefUsed.difference(previous.reliefUsed);
        if (newlyRelieved.contains(widget.viewerSeat)) {
          return cue(
            '🌾',
            'Catch-up aid: +1 resource',
            'A dry-roll safety net for players behind on points',
            color: teal,
          );
        }
        return null;
      case PlaceVillage():
        if (previous.phase == MatchPhase.setupVillage &&
            previous.setupStep >= previous.players.length &&
            actor == widget.viewerSeat) {
          final earned = <String>[];
          for (final good in Resource.values) {
            final amount =
                (state.players[actor].stores[good] ?? 0) -
                (previous.players[actor].stores[good] ?? 0);
            if (amount > 0) earned.add('$amount ${good.displayName}');
          }
          if (earned.isNotEmpty) {
            return cue(
              '🌾',
              'Starting village harvest',
              earned.join(', '),
              color: teal,
            );
          }
        }
        return null;
      case PlaceRoad():
      case UpgradeSite():
      case DevelopTown():
      case FortifyTown():
      case RecruitGuard():
      case ActivateGuard():
      case PromoteGuard():
      case MoveGuard():
        return null;
      case MoveBandit():
        // Bandit movement and theft are already animated on the board.
        return null;
      case RespondTactical():
        if (event.choice == TacticalChoice.intercept) {
          return cue(
            '🛡️',
            '$prefix blocks a theft',
            'Guard to the rescue',
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
        return cue('🔥', 'Raider assault!', state.lastInvasion, color: coral);
      case BankExchange():
        return cue(
          '🪙',
          '$prefix visits the market',
          'A trade with the bank',
          color: gold,
        );
      case ProposeTrade():
        // The incoming-trade dialog already announces computer proposals.
        if (isAi) return null;
        if (actor != widget.viewerSeat &&
            event.target != -1 &&
            event.target != widget.viewerSeat) {
          return null;
        }
        return cue(
          '🤝',
          '$prefix sends an offer',
          '${tradeBundleText(event.gives)} for ${tradeBundleText(event.wants)}',
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
        final offer = proposalForResponse(state, event);
        final offeredByViewer =
            offer != null &&
            tradeProposerForEvent(state, state.events.indexOf(offer)) ==
                widget.viewerSeat;
        return cue(
          event.accept ? '🎉' : '📨',
          event.accept
              ? offeredByViewer
                    ? 'YOUR TRADE WAS ACCEPTED!'
                    : 'TRADE ACCEPTED!'
              : 'Offer declined',
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
        final playedHand = previous.players[actor].cards;
        if (event.handIndex >= 0 &&
            event.handIndex < playedHand.length &&
            {
              CardPower.freeRoad,
              CardPower.freeFort,
              CardPower.activate,
              CardPower.promote,
              CardPower.exhaust,
              CardPower.moveBandit,
              CardPower.massExhaust,
            }.contains(playedHand[event.handIndex].definition.power)) {
          return null; // Board effects are already visible in situ.
        }
        final hand = playedHand;
        final card = event.handIndex >= 0 && event.handIndex < hand.length
            ? hand[event.handIndex].definition
            : null;
        if (card?.power == CardPower.massRaid) {
          return cue(
            '👑',
            '$prefix unleashes the Royal Audit!',
            'Every rival pays a random good. The taxman takes no prisoners.',
            color: coral,
          );
        }
        if (card?.power == CardPower.massExhaust) {
          return cue(
            '😤',
            '$prefix suspends a whole squad!',
            'Rival Guards on this hex are on involuntary holiday.',
            color: violet,
          );
        }
        if (card?.id == 'sheep-napping') {
          return cue(
            '🐑',
            '$prefix launches a sheep conspiracy!',
            'One rival is about to lose a good to the woolly underworld.',
            color: gold,
          );
        }
        if (card?.id == 'castle-of-spite') {
          return cue(
            '🏰',
            '$prefix builds the Spite Castle!',
            'An expensive-looking monument to petty rivalry.',
            color: gold,
          );
        }
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
      case RedactedNetworkEvent():
        return null;
    }
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _reply?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.targetSeat != null) {
      final cue = _cue;
      final name = cue == null ? '' : widget.state.players[cue.seat].id;
      final description = cue == null
          ? ''
          : cue.title
                .replaceFirst(name, '')
                .replaceFirst(RegExp(r'^[:\s]+'), '')
                .trim();
      return IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: cue == null
              ? const SizedBox.shrink(key: ValueKey('player-cue-empty'))
              : Align(
                  key: ValueKey('player-cue-${cue.index}'),
                  alignment: cue.isEmote
                      ? Alignment.bottomLeft
                      : Alignment.centerLeft,
                  child: Semantics(
                    label: cue.isEmote
                        ? '$name reacts ${cue.emoji}'
                        : cue.title,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xff172a33),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cue.color),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 2,
                        ),
                        child: cue.isEmote
                            ? GameEmoteIcon(cue.emoji, size: 17)
                            : SizedBox(
                                width: 110,
                                child: Row(
                                  children: [
                                    GameEmoteIcon(cue.emoji, size: 18),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        description.isNotEmpty
                                            ? description
                                            : cue.detail,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          height: 1.05,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
        ),
      );
    }
    if (widget.emotesOnly) {
      final cue = _cue;
      return IgnorePointer(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 230),
            child: cue == null
                ? const SizedBox.shrink(key: ValueKey('center-emote-empty'))
                : Column(
                    key: ValueKey('center-emote-${cue.index}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GameEmoteIcon(cue.emoji, size: 94),
                      const SizedBox(height: 5),
                      Text(
                        widget.state.players[cue.seat].id,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 9, color: Colors.black)],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }
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
                : GameEmoteIcon(
                    cue.emoji,
                    size: MediaQuery.sizeOf(context).width < 900 ? 22 : 32,
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
    const yellow = Color(0xffffd449);
    const deep = Color(0xffc58a20);
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
    canvas.drawCircle(const Offset(19, 21), 16, Paint()..color = yellow);
    canvas.drawCircle(
      const Offset(13.2, 18),
      3.5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(const Offset(25, 18), 3.5, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(14.4, 17.6),
      1.7,
      Paint()..color = const Color(0xff302217),
    );
    canvas.drawCircle(
      const Offset(26.2, 17.6),
      1.7,
      Paint()..color = const Color(0xff302217),
    );
    final brow = Paint()
      ..color = const Color(0xff92501b)
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
        ..color = const Color(0xff82501b)
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      const Offset(30.2, 22.7),
      2,
      Paint()..color = const Color(0xffffeb9a),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CheekyDevilPainter oldDelegate) => false;
}
