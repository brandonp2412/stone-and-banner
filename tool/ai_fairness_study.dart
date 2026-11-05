import 'dart:convert';
import 'dart:io';

import 'package:stone_and_banner/engine/balance.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/simulation.dart';

/// Controlled baseline-rules comparison: repeat each seed and board with every
/// cyclic lineup rotation, so every bot visits every opening seat once.
///
/// Usage: dart run tool/ai_fairness_study.dart FIRST_SEED COUNT ROUND_CAP OUT_DIR
/// Never change production rules or credit capped games to any track.
void main(List<String> args) {
  if (args.length != 4) {
    stderr.writeln(
      'Usage: dart run tool/ai_fairness_study.dart FIRST_SEED COUNT '
      'ROUND_CAP OUT_DIR',
    );
    exitCode = 64;
    return;
  }
  final firstSeed = int.parse(args[0]);
  final count = int.parse(args[1]);
  final cap = int.parse(args[2]);
  if (count < 1 || cap < 1) {
    throw ArgumentError('COUNT and ROUND_CAP must be positive');
  }
  final dir = Directory(args[3])..createSync(recursive: true);
  final records = <Map<String, Object?>>[];
  final started = Stopwatch()..start();

  for (final seats in [3, 4]) {
    for (var seed = firstSeed; seed < firstSeed + count; seed++) {
      // The fourth seat repeats a track; rotating removes position confounding.
      final base = List<BalanceBot>.generate(seats, (i) {
        final track = StrategyDeck.values[(i + seed % 3) % 3];
        final temperament = (i + seed ~/ 3) % 3;
        return BalanceBot(
          track,
          trade: temperament != 0,
          defend: temperament != 1,
        );
      });
      for (var rotation = 0; rotation < seats; rotation++) {
        final lineup = List<BalanceBot>.generate(
          seats,
          (seat) => base[(seat + rotation) % seats],
        );
        final result = BalanceSimulation.run(
          seed: seed,
          seats: seats,
          maxRounds: cap,
          balance: MatchBalance.baseline,
          lineup: lineup,
        );
        final state = result.state;
        final replay = MatchEngine.importReplay(
          MatchEngine.exportReplay(state),
        );
        if (MatchEngine.snapshot(state) != MatchEngine.snapshot(replay)) {
          throw StateError(
            'Replay mismatch: seed=$seed seats=$seats rotation=$rotation',
          );
        }
        for (final resource in Resource.values) {
          var total = state.bank[resource] ?? 0;
          for (final player in state.players) {
            final amount = player.stores[resource] ?? 0;
            if (amount < 0) {
              throw StateError('Negative resource at seed=$seed');
            }
            total += amount;
          }
          for (final offer in state.offers) {
            if (offer.give == resource) total += offer.giveCount;
          }
          if (total != MatchEngine.bankSupply) {
            throw StateError(
              'Resource conservation at seed=$seed resource=$resource: $total',
            );
          }
        }
        for (final track in StrategyDeck.values) {
          final physical =
              (state.drawPiles[track]?.length ?? 0) +
              (state.discardPiles[track]?.length ?? 0) +
              state.players.fold<int>(
                0,
                (n, player) =>
                    n +
                    player.cards.where((card) => card.track == track).length,
              );
          if (physical != StrategyCards.deck(track).length) {
            throw StateError('Card conservation at seed=$seed track=$track');
          }
        }
        final winner = result.winner;
        final scores = [
          for (var seat = 0; seat < seats; seat++)
            MatchEngine.score(state, seat),
        ];
        if (winner != null && scores[winner] < 15) {
          throw StateError('Premature victory at seed=$seed');
        }
        records.add({
          'seed': seed,
          'boardSeed': seed * 7 + 11,
          'seats': seats,
          'rotation': rotation,
          'roundCap': cap,
          'finished': result.finished,
          'winnerSeat': winner,
          'winnerTrack': winner == null ? null : lineup[winner].track.name,
          'seatTracks': [for (final bot in lineup) bot.track.name],
          'seatTrade': [for (final bot in lineup) bot.trade],
          'seatDefend': [for (final bot in lineup) bot.defend],
          'scores': scores,
          'round': state.round,
          'turns': result.turns,
          'events': state.events.length,
        });
      }
    }
  }

  started.stop();
  final file = File('${dir.path}/records.jsonl');
  file.writeAsStringSync("${records.map(jsonEncode).join('\n')}\n");
  final summary = {
    'policy': 'BalanceSimulation track-focused heuristic bots',
    'rules': 'MatchBalance.baseline',
    'firstSeed': firstSeed,
    'lastSeed': firstSeed + count - 1,
    'roundCap': cap,
    'seedBlocksPerPlayerCount': count,
    'games': records.length,
    'durationMs': started.elapsedMilliseconds,
    'records': file.path,
    'cells': [
      for (final seats in [3, 4])
        {
          'seats': seats,
          'games': records.where((r) => r['seats'] == seats).length,
          'finished': records
              .where((r) => r['seats'] == seats && r['finished'] == true)
              .length,
          'firstSeatWins': records
              .where((r) => r['seats'] == seats && r['winnerSeat'] == 0)
              .length,
        },
    ],
  };
  final path = '${dir.path}/summary.json';
  File(path).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
  );
  stdout.writeln(jsonEncode(summary));
}
