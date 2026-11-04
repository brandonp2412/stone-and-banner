import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/match.dart';

/// Reproducible quality probe, not a proof of human-match strength.
///
/// One heuristic seat rotates against two seeded legal-random opponents.
/// Match dice and event effects still use the engine's saved deterministic
/// seed, never the benchmark's policy RNG.
void main(List<String> args) {
  final firstSeed = args.isEmpty ? 601 : int.parse(args.first);
  final games = args.length < 2 ? 24 : int.parse(args[1]);
  final roundLimit = args.length < 3 ? 30 : int.parse(args[2]);
  const bot = HeuristicAi();
  var heuristicScore = 0;
  var randomScore = 0;
  var wins = 0;
  var heuristicRoads = 0;
  var heuristicVillages = 0;
  var heuristicUpgrades = 0;
  var heuristicExchanges = 0;
  var finished = 0;
  var totalSteps = 0;

  for (var seed = firstSeed; seed < firstSeed + games; seed++) {
    final rng = math.Random(seed ^ 0x31415926);
    final aiSeat = seed % 3;
    var state = MatchEngine.newGame(
      ['A', 'B', 'C'],
      seed,
      boardSeed: seed * 7 + 11,
    );
    var turnActions = 0;

    MatchEvent randomMove() {
      final legal = AiLegalActions(state);
      switch (state.phase) {
        case MatchPhase.setupVillage:
          return legal.villages[rng.nextInt(legal.villages.length)];
        case MatchPhase.setupRoad:
          return legal.roads[rng.nextInt(legal.roads.length)];
        case MatchPhase.roll:
          final (a, b) = MatchEngine.expectedDice(state);
          return RollDice(a, b);
        case MatchPhase.bandit:
          return legal.banditMoves[rng.nextInt(legal.banditMoves.length)];
        case MatchPhase.invasion:
          return const ResolveInvasion();
        case MatchPhase.actions:
          if (turnActions >= 8) return const EndTurn();
          final options = <MatchEvent>[
            ...legal.villages,
            ...legal.roads,
            ...legal.upgrades,
            ...legal.developments,
            ...legal.exchanges,
            ...legal.cards,
            const EndTurn(),
            const EndTurn(),
          ];
          return options[rng.nextInt(options.length)];
        case MatchPhase.finished:
          throw StateError('Finished game was advanced');
      }
    }

    for (
      var i = 0;
      i < 3000 &&
          state.phase != MatchPhase.finished &&
          state.round <= roundLimit;
      i++
    ) {
      final who = state.tactical?.responder ?? state.active;
      final event = state.tactical != null
          ? bot.choose(state)!
          : who == aiSeat
          ? bot.choose(state)!
          : randomMove();
      if (state.tactical == null &&
          state.phase == MatchPhase.actions &&
          who == aiSeat) {
        if (event is PlaceRoad) heuristicRoads++;
        if (event is PlaceVillage) heuristicVillages++;
        if (event is UpgradeSite) heuristicUpgrades++;
        if (event is BankExchange) heuristicExchanges++;
      }
      if (event is EndTurn || event is RollDice) {
        turnActions = 0;
      } else if (state.phase == MatchPhase.actions) {
        turnActions++;
      }
      final view = AiActionAdapter.observe(state, who);
      state = AiActionAdapter.applySelected(state, view, event);
      totalSteps++;
    }
    if (state.phase == MatchPhase.finished) finished++;
    if (state.phase != MatchPhase.finished && state.round <= roundLimit) {
      throw StateError('Step cap reached for seed $seed');
    }
    final scores = [
      for (var seat = 0; seat < 3; seat++) MatchEngine.score(state, seat),
    ];
    heuristicScore += scores[aiSeat];
    randomScore += scores.reduce((a, b) => a + b) - scores[aiSeat];
    if (MatchEngine.winner(state) == aiSeat) wins++;
  }

  stdout.writeln(
    jsonEncode({
      'firstSeed': firstSeed,
      'games': games,
      'roundLimit': roundLimit,
      'heuristicWinCount': wins,
      'finished': finished,
      'heuristicMeanScore': heuristicScore / games,
      'randomMeanScorePerSeat': randomScore / (games * 2),
      'heuristicRoads': heuristicRoads,
      'heuristicVillages': heuristicVillages,
      'heuristicUpgrades': heuristicUpgrades,
      'heuristicExchanges': heuristicExchanges,
      'totalSteps': totalSteps,
      'caveat':
          'Seeded legal-random policy is not a human or balance benchmark',
    }),
  );
}
