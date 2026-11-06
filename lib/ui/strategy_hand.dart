import '../network/room_protocol.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/cards.dart';
import '../engine/game.dart';
import '../engine/match.dart';

const _trackColors = <StrategyDeck, Color>{
  StrategyDeck.innovation: Color(0xff2c8063),
  StrategyDeck.commerce: Color(0xffad8121),
  StrategyDeck.governance: Color(0xff4279b9),
};

/// An original drawn motif: no external or game-source card artwork.
class _CardMotif extends CustomPainter {
  const _CardMotif(this.track, this.seed);
  final StrategyDeck track;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final base = _trackColors[track]!;
    final bounds = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(11)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, Colors.black, .47)!],
        ).createShader(bounds),
    );
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: .78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final v = (seed % 7) + 3;
    final r = math.min(size.width, size.height) * .27;
    final star = Path();
    for (var i = 0; i <= 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final radius = i.isEven ? r : r * (.60 + v / 40);
      final point = Offset(
        cx + radius * math.cos(a),
        cy + radius * math.sin(a),
      );
      if (i == 0) {
        star.moveTo(point.dx, point.dy);
      } else {
        star.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(star, stroke);
    canvas.drawCircle(Offset(cx, cy), r * .26, stroke);
    canvas.drawLine(
      Offset(cx - r * 1.35, cy + r * .8),
      Offset(cx + r * 1.35, cy + r * .8),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_CardMotif old) => old.track != track || old.seed != seed;
}

class StrategyHand extends StatelessWidget {
  const StrategyHand({
    super.key,
    required this.state,
    required this.onEvent,
    this.onlineOptions,
  });
  final MatchState state;
  final ValueChanged<MatchEvent> onEvent;
  final Map? onlineOptions;

  String _optionLabel(StrategyCard card, PlayStrategyCard option) {
    switch (card.power) {
      case CardPower.fixedGoods:
        return 'Collect listed supplies';
      case CardPower.chooseBasic:
      case CardPower.chooseCommodity:
        return 'Collect ${card.amount} ${option.receive!.name}';
      case CardPower.freeRoad:
        return 'Build road on edge ${option.vertex}';
      case CardPower.freeFort:
        return 'Fortify site ${option.vertex}';
      case CardPower.swap:
      case CardPower.portSwap:
      case CardPower.leverageSwap:
        final give = card.power == CardPower.leverageSwap ? 2 : 1;
        final receive = card.power == CardPower.portSwap ? 2 : 1;
        return 'Give $give ${option.give!.name} · receive $receive ${option.receive!.name}';
      case CardPower.activate:
        return 'Activate Knight at junction ${option.vertex}';
      case CardPower.promote:
        return 'Promote Knight at junction ${option.vertex}';
      case CardPower.exhaust:
        return 'Stand down rival Knight at junction ${option.vertex}';
      case CardPower.moveBandit:
        return 'Move Bandit to tile ${option.tile} '
            '(${state.board.tiles[option.tile!].land.name})';
      case CardPower.seizeGood:
        return 'Take ${option.receive!.name} from '
            '${state.players[option.target!].id}';
    }
  }

  Future<void> _showCard(BuildContext context, int handIndex) async {
    final card = state.current.cards[handIndex].definition;
    final options = onlineOptions == null
        ? MatchEngine.legalCardPlays(state, handIndex)
        : [
            for (final e in (onlineOptions!['$handIndex'] as List? ?? []))
              RoomProtocol.eventFromJson(Map<String, dynamic>.from(e as Map))
                  as PlayStrategyCard,
          ];

    // Large trade/raid choice sets are split into one decision per screen.
    // Only a confirmed option is sent to the deterministic reducer.
    final groups = <String, List<PlayStrategyCard>>{};
    final grouped = {
      CardPower.swap,
      CardPower.portSwap,
      CardPower.leverageSwap,
      CardPower.seizeGood,
    }.contains(card.power);
    if (grouped) {
      for (final option in options) {
        final title = card.power == CardPower.seizeGood
            ? 'Player ${state.players[option.target!].id}'
            : 'Give ${card.power == CardPower.leverageSwap ? 2 : 1} ${option.give!.name}';
        groups.putIfAbsent(title, () => []).add(option);
      }
    }
    String? selectedGroup;
    PlayStrategyCard? selectedOption;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) {
          final visible = grouped
              ? (selectedGroup == null
                    ? <PlayStrategyCard>[]
                    : groups[selectedGroup]!)
              : options;
          final screenHeight = MediaQuery.sizeOf(sheetContext).height;
          final compact =
              !grouped && options.length <= 5 && screenHeight >= 700;
          return SafeArea(
            child: SizedBox(
              height: screenHeight * (compact ? .58 : .78),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          height: 92,
                          width: 72,
                          child: CustomPaint(
                            painter: _CardMotif(
                              card.track,
                              card.id.codeUnits.fold<int>(
                                0,
                                (value, unit) => value * 31 + unit,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card.track.name.toUpperCase(),
                                style: TextStyle(
                                  color: _trackColors[card.track],
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                card.name,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .headlineSmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      card.description,
                      style: Theme.of(sheetContext).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    if (selectedGroup != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => refresh(() {
                            selectedGroup = null;
                            selectedOption = null;
                          }),
                          icon: const Icon(Icons.arrow_back),
                          label: Text(selectedGroup!),
                        ),
                      ),
                    Text(
                      options.isEmpty
                          ? 'No legal play right now.'
                          : grouped && selectedGroup == null
                          ? (card.power == CardPower.seizeGood
                                ? 'Choose a rival'
                                : 'Choose what to give')
                          : card.power == CardPower.fixedGoods
                          ? 'Effect'
                          : 'Choose a legal target or exchange',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: options.isEmpty
                          ? const Center(
                              child: Text(
                                'Keep this card for a future turn, or discard it.',
                              ),
                            )
                          : grouped && selectedGroup == null
                          ? ListView(
                              children: [
                                for (final entry in groups.entries)
                                  ListTile(
                                    title: Text(entry.key),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => refresh(() {
                                      selectedGroup = entry.key;
                                      selectedOption = null;
                                    }),
                                  ),
                              ],
                            )
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (_, i) {
                                final option = visible[i];
                                final selected = identical(
                                  selectedOption,
                                  option,
                                );
                                return ListTile(
                                  selected: selected,
                                  leading: Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: _trackColors[card.track],
                                  ),
                                  title: Text(_optionLabel(card, option)),
                                  onTap: () =>
                                      refresh(() => selectedOption = option),
                                );
                              },
                            ),
                    ),
                    if (selectedOption != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _optionLabel(card, selectedOption!),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ),
                    if (options.isNotEmpty)
                      FilledButton.icon(
                        onPressed: selectedOption == null
                            ? null
                            : () {
                                final confirmed = selectedOption!;
                                Navigator.pop(sheetContext);
                                onEvent(confirmed);
                              },
                        icon: const Icon(Icons.check),
                        label: const Text('Play selected card'),
                      ),
                    TextButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Discard this card?'),
                            content: Text(
                              '${card.name} will leave your hand without using its effect.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Keep card'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Discard'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                          onEvent(DiscardStrategyCard(handIndex));
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Discard this card'),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Strategy hand · ${state.current.cards.length}/${StrategyCards.handLimit}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              state.lastCardEvent.isEmpty
                  ? 'Develop Town tracks to qualify for event-die draws.'
                  : state.lastCardEvent,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (var i = 0; i < state.current.cards.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(
                  label:
                      '${state.current.cards[i].definition.track.name} card: '
                      '${state.current.cards[i].definition.name}',
                  child: OutlinedButton(
                    onPressed: () => _showCard(context, i),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 43,
                          height: 56,
                          child: CustomPaint(
                            painter: _CardMotif(
                              state.current.cards[i].track,
                              state.current.cards[i].definition.id.codeUnits
                                  .fold<int>(
                                    0,
                                    (value, unit) => value * 31 + unit,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.current.cards[i].definition.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                state.current.cards[i].track.name,
                                style: TextStyle(
                                  color:
                                      _trackColors[state
                                          .current
                                          .cards[i]
                                          .track],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
