import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

/// Seeded AI-match audit. The "human" is a reproducible legal-random input
/// simulator, NOT a measured human participant. Neither policy sees future
/// randomness; both submit actions through AiActionAdapter.applySelected.
///
/// Usage: `dart run tool/ai_stability_corpus.dart <first-seed> <seeds> <max-rounds> <evidence-directory>`
/// Runs two policies (all heuristic, one simulated human) at 3 and 4 seats.
/// The reducer currently disallows two seats; report this coverage limit.
void main(List<String> args) {
  final firstSeed = args.isEmpty ? 6400 : int.parse(args[0]);
  final seedCount = args.length < 2 ? 30 : int.parse(args[1]);
  final roundCap = args.length < 3 ? 60 : int.parse(args[2]);
  final output = Directory(args.length < 4 ? 'build/ai-stability' : args[3])
    ..createSync(recursive: true);
  if (seedCount < 1 || roundCap < 1) {
    throw ArgumentError('seeds and max-rounds must be positive');
  }

  final stopwatch = Stopwatch()..start();
  final records = <Map<String, Object?>>[];
  final failures = <Map<String, Object?>>[];
  final eventTypes = <String, int>{};
  final tacticalKinds = <String, int>{};
  final decisionsUs = <int>[];
  final applicationsUs = <int>[];
  var twoSeatSupported = true;
  String? twoSeatError;
  try {
    MatchEngine.newGame(['Seat-0', 'Seat-1'], firstSeed);
  } catch (e) {
    twoSeatSupported = false;
    twoSeatError = e.toString();
  }

  for (final seats in [3, 4]) {
    for (final mode in ['allAi', 'simulatedHuman']) {
      for (var seed = firstSeed; seed < firstSeed + seedCount; seed++) {
        final humanSeat = mode == 'simulatedHuman' ? seed % seats : -1;
        final names = List.generate(seats, (i) => 'Seat-$i');
        final rng = math.Random(seed ^ (seats << 18) ^ 0x30a0e);
        final elapsed = Stopwatch()..start();
        var state = MatchEngine.newGame(names, seed, boardSeed: seed * 7 + 11);
        var steps = 0;
        var maxDecisionUs = 0;
        var longestRoadTies = 0;
        var scoreTies = 0;
        final localEvents = <String, int>{};
        String? failed;
        String? lastAction;
        try {
          while (state.phase != MatchPhase.finished &&
              state.round <= roundCap) {
            if (steps >= roundCap * seats * 32 + seats * 5) {
              throw StateError('event cap exhausted at round ${state.round}');
            }
            final actor = state.tactical?.responder ?? state.active;
            final phase = state.phase;
            final previousTactical = state.tactical?.kind.name;
            final watch = Stopwatch()..start();
            final view = AiActionAdapter.observe(state, actor);
            if (view.legalActions.isEmpty) {
              throw StateError('no legal actions for actor $actor at $phase');
            }
            final chosen = actor == humanSeat
                ? _legalRandom(view, rng)
                : const HeuristicAi().choose(state);
            watch.stop();
            final decisionUs = watch.elapsedMicroseconds;
            decisionsUs.add(decisionUs);
            maxDecisionUs = math.max(maxDecisionUs, decisionUs);
            if (chosen == null) {
              throw StateError('policy returned null at $phase');
            }
            lastAction = jsonEncode(chosen.toJson());
            final allowed = view.legalActions.any(
              (event) => jsonEncode(event.toJson()) == lastAction,
            );
            if (!allowed) {
              throw StateError(
                'policy action absent from scoped legal whitelist',
              );
            }
            final applyWatch = Stopwatch()..start();
            final next = AiActionAdapter.applySelected(state, view, chosen);
            applyWatch.stop();
            applicationsUs.add(applyWatch.elapsedMicroseconds);
            if (next.events.length != state.events.length + 1) {
              throw StateError('event append did not advance by one');
            }
            _verifySupply(next, seed, steps);
            _verifyScores(next);
            if (chosen is PlaceRoad ||
                chosen is PlaceVillage ||
                next.longestRoadHolder != state.longestRoadHolder) {
              final lengths = [
                for (var seat = 0; seat < seats; seat++)
                  MatchEngine.longestRoad(next, seat),
              ];
              final largest = lengths.reduce(math.max);
              final tied = lengths.where((n) => n == largest).length > 1;
              if (tied && largest >= 5) longestRoadTies++;
              final holder = next.longestRoadHolder;
              if (holder != null &&
                  (largest < 5 || lengths[holder] != largest)) {
                throw StateError(
                  'invalid longest-road holder $holder: $lengths',
                );
              }
              if (holder == null && largest >= 5 && !tied) {
                throw StateError('unique longest road has no holder: $lengths');
              }
            }
            final scores = [
              for (var seat = 0; seat < seats; seat++)
                MatchEngine.score(next, seat),
            ];
            if (scores.where((n) => n == scores.reduce(math.max)).length > 1) {
              scoreTies++;
            }
            final eventName = chosen.toJson()['type'] as String;
            eventTypes.update(
              eventName,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
            localEvents.update(
              eventName,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
            if (previousTactical != null) {
              tacticalKinds.update(
                previousTactical,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
            }
            state = next;
            steps++;
            if (elapsed.elapsed > const Duration(seconds: 45)) {
              throw StateError('per-match wall-clock limit exceeded');
            }
          }
          final imported = MatchEngine.importReplay(
            MatchEngine.exportReplay(state),
          );
          if (MatchEngine.snapshot(imported) != MatchEngine.snapshot(state)) {
            throw StateError('export/import replay snapshot mismatch');
          }
          // Also replay event objects directly from the same original seed.
          final direct = MatchEngine.replay(
            names,
            seed,
            state.events,
            boardSeed: seed * 7 + 11,
          );
          if (MatchEngine.snapshot(direct) != MatchEngine.snapshot(state)) {
            throw StateError('direct replay snapshot mismatch');
          }
        } catch (error, stack) {
          failed = error.toString();
          final failure = {
            'seed': seed,
            'seats': seats,
            'mode': mode,
            'humanSeat': humanSeat,
            'step': steps,
            'round': state.round,
            'phase': state.phase.name,
            'lastAction': lastAction,
            'error': failed,
            'stack': stack.toString().split('\n').take(9).join('\n'),
            'eventPrefix': state.events.map((e) => e.toJson()).toList(),
          };
          failures.add(failure);
        }
        elapsed.stop();
        final scores = [
          for (var seat = 0; seat < seats; seat++)
            MatchEngine.score(state, seat),
        ];
        records.add({
          'seed': seed,
          'boardSeed': seed * 7 + 11,
          'seats': seats,
          'mode': mode,
          'humanSeat': humanSeat,
          'round': state.round,
          'steps': steps,
          'durationMs': elapsed.elapsedMilliseconds,
          'maxDecisionUs': maxDecisionUs,
          'finished': state.phase == MatchPhase.finished,
          'winner': MatchEngine.winner(state),
          'scores': scores,
          'longestRoadTies': longestRoadTies,
          'scoreTies': scoreTies,
          'invasions': state.invasions,
          'roadHolder': state.longestRoadHolder,
          'events': localEvents,
          'eventHash64': _eventHash(state.events),
          'failure': failed,
        });
      }
    }
  }
  stopwatch.stop();
  int percentile(List<int> sorted, int numerator) {
    if (sorted.isEmpty) return 0;
    return sorted[((sorted.length - 1) * numerator) ~/ 100];
  }

  final sortedDecisions = decisionsUs.toList()..sort();
  final sortedApplications = applicationsUs.toList()..sort();
  final cohorts = <Map<String, Object?>>[];
  for (final seats in [3, 4]) {
    for (final mode in ['allAi', 'simulatedHuman']) {
      final sample = records
          .where((r) => r['seats'] == seats && r['mode'] == mode)
          .toList();
      final finished = sample.where((r) => r['finished'] == true).toList();
      final wins = [
        for (var seat = 0; seat < seats; seat++)
          finished.where((r) => r['winner'] == seat).length,
      ];
      final seatScore = [
        for (var seat = 0; seat < seats; seat++)
          sample.fold<int>(0, (n, r) => n + (r['scores'] as List<int>)[seat]) /
              sample.length,
      ];
      cohorts.add({
        'seats': seats,
        'mode': mode,
        'games': sample.length,
        'finished': finished.length,
        'capped': sample.length - finished.length,
        'winsByOpeningSeat': wins,
        'meanScoreByOpeningSeat': seatScore,
        'firstSeatWinsOfFinished': finished.isEmpty
            ? null
            : wins[0] / finished.length,
        'simulatedHumanWins': mode == 'simulatedHuman'
            ? finished.where((r) => r['winner'] == r['humanSeat']).length
            : null,
        'meanSteps':
            sample.fold<int>(0, (n, r) => n + (r['steps'] as int)) /
            sample.length,
        'maxMatchMs': sample
            .map((r) => r['durationMs'] as int)
            .reduce(math.max),
        'scoreTiesObserved': sample.fold<int>(
          0,
          (n, r) => n + (r['scoreTies'] as int),
        ),
        'roadTiesObserved': sample.fold<int>(
          0,
          (n, r) => n + (r['longestRoadTies'] as int),
        ),
      });
    }
  }
  final summary = {
    'firstSeed': firstSeed,
    'lastSeed': firstSeed + seedCount - 1,
    'seedCountPerCohort': seedCount,
    'roundCap': roundCap,
    'totalGames': records.length,
    'failures': failures.length,
    'twoSeatSupported': twoSeatSupported,
    'twoSeatError': twoSeatError,
    'scope': 'pure Dart reducer, 3–4 seats; random legal policy simulates input, not actual humans',
    'cohorts': cohorts,
    'eventTypes': eventTypes,
    'tacticalResponsesByWindow': tacticalKinds,
    'decisionUs': {
      'p50': percentile(sortedDecisions, 50),
      'p95': percentile(sortedDecisions, 95),
      'p99': percentile(sortedDecisions, 99),
      'max': sortedDecisions.isEmpty ? 0 : sortedDecisions.last,
    },
    'applicationUs': {
      'p50': percentile(sortedApplications, 50),
      'p95': percentile(sortedApplications, 95),
      'p99': percentile(sortedApplications, 99),
      'max': sortedApplications.isEmpty ? 0 : sortedApplications.last,
    },
    'wallClockMs': stopwatch.elapsedMilliseconds,
  };
  File('${output.path}/records.jsonl')
      .writeAsStringSync('${records.map(jsonEncode).join('\n')}\n');
  File('${output.path}/failures.jsonl').writeAsStringSync(
    failures.map(jsonEncode).join('\n') + (failures.isEmpty ? '' : '\n'),
  );
  File('${output.path}/summary.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
  );
  stdout.writeln(jsonEncode(summary));
  if (failures.isNotEmpty) exitCode = 1;
}

MatchEvent _legalRandom(AiTurnView view, math.Random rng) {
  final candidates = view.legalActions;
  if (candidates.first is RespondTactical) {
    if (rng.nextInt(3) == 0) {
      final passing = candidates.whereType<RespondTactical>().where(
        (event) => event.choice == TacticalChoice.pass,
      );
      if (passing.isNotEmpty) return passing.first;
    }
    return candidates[rng.nextInt(candidates.length)];
  }
  if (view.phase == MatchPhase.actions) {
    final end = candidates.whereType<EndTurn>().first;
    if (view.actionsSinceRoll >= 8 || rng.nextInt(4) == 0) return end;
    final nonEnd = candidates.where((e) => e is! EndTurn).toList();
    return nonEnd.isEmpty ? end : nonEnd[rng.nextInt(nonEnd.length)];
  }
  if (view.phase == MatchPhase.roll) {
    return candidates.whereType<RollDice>().single;
  }
  return candidates[rng.nextInt(candidates.length)];
}

void _verifySupply(MatchState state, int seed, int step) {
  for (final resource in Resource.values) {
    final stock = state.bank[resource] ?? 0;
    var total = stock;
    if (stock < 0) {
      throw StateError('negative bank ${resource.name}: seed $seed step $step');
    }
    for (final player in state.players) {
      final count = player.stores[resource] ?? 0;
      if (count < 0) {
        throw StateError(
          'negative hand ${resource.name}: seed $seed step $step',
        );
      }
      total += count;
    }
    for (final offer in state.offers) {
      if (offer.give == resource) total += offer.giveCount;
    }
    if (total != MatchEngine.bankSupply) {
      throw StateError('supply ${resource.name}=$total: seed $seed step $step');
    }
  }
  for (final track in StrategyDeck.values) {
    final inHand = state.players.fold<int>(
      0,
      (total, p) => total + p.cards.where((card) => card.track == track).length,
    );
    final physical =
        inHand +
        (state.drawPiles[track]?.length ?? 0) +
        (state.discardPiles[track]?.length ?? 0);
    if (physical != StrategyCards.deck(track).length) {
      throw StateError(
        'card conservation ${track.name}=$physical: seed $seed step $step',
      );
    }
  }
}

/// FNV-1a over canonical ordered event JSON, for byte-identical rerun audits.
/// This is an audit checksum, not a security digest.
String _eventHash(List<MatchEvent> events) {
  var hash = 0xcbf29ce484222325;
  final bytes = utf8.encode(jsonEncode(events.map((e) => e.toJson()).toList()));
  for (final byte in bytes) {
    hash = ((hash ^ byte) * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

void _verifyScores(MatchState state) {
  final scores = [
    for (var seat = 0; seat < state.players.length; seat++)
      MatchEngine.score(state, seat),
  ];
  if (scores.any((score) => score < 0)) {
    throw StateError('negative scores $scores');
  }
  final winner = MatchEngine.winner(state);
  if (state.phase == MatchPhase.finished) {
    if (winner == null || scores[winner] < 15) {
      throw StateError('finished before 15: $scores');
    }
  } else if (winner != null) {
    throw StateError('score >= 15 without finished phase: $scores');
  }
}
