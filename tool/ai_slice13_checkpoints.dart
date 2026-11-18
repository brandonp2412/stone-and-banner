import 'dart:convert';
import 'dart:io';

// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/simulation.dart';
import 'package:stone_and_banner/replay_codes.dart';

/// Generate genuine accepted-event replay checkpoints for manual UI testing.
void main() {
  final output = Directory(
    '/home/brandon/.local/state/stone-and-banner/e2e/'
    'stone-banner-ai-e2e-13/checkpoints',
  )..createSync(recursive: true);
  final best = <String, ({String code, Map<String, Object?> info})>{};
  for (var seed = 1; seed <= 65; seed++) {
    final simulated = BalanceSimulation.run(seed: seed, maxRounds: 75);
    var state = MatchEngine.newGame(
      ['Bot-0', 'Bot-1', 'Bot-2'],
      seed,
      boardSeed: seed * 7 + 11,
    );
    void record(String label, {String? detail}) {
      final replay = MatchEngine.exportReplay(state);
      final compact = ReplayCodes.compact(replay);
      if (best[label] case final prior?
          when prior.code.length <= compact.length) {
        return;
      }
      best[label] = (
        code: compact,
        info: {
          'seed': seed,
          'eventCount': state.events.length,
          'phase': state.phase.name,
          'active': state.active,
          'rate': MatchEngine.tradeRate(state, state.active),
          'codeLength': compact.length,
          'detail': detail ?? '',
        },
      );
    }

    for (final event in simulated.state.events) {
      if (state.phase == MatchPhase.actions) {
        final rate = MatchEngine.tradeRate(state, state.active);
        final available = Resource.values.where(
          (good) =>
              (state.current.stores[good] ?? 0) >= rate &&
              Resource.values.any(
                (take) => take != good && (state.bank[take] ?? 0) > 0,
              ),
        );
        if (available.isNotEmpty && [2, 3, 4].contains(rate)) {
          record('bank-$rate-to-1', detail: 'Give ' + available.first.name);
        }
        if (state.current.stores.values.any((count) => count > 0)) {
          record('offer-ready');
        }
        if (state.offers.isNotEmpty) {
          final offer = state.offers.first;
          record(
            'standing-offer',
            detail:
                'Proposer ' +
                offer.proposer.toString() +
                ', target ' +
                offer.target.toString() +
                ', id ' +
                offer.id.toString(),
          );
        }
      }
      if (state.tactical != null) {
        record('tactical-' + state.tactical!.kind.name);
      }
      state = MatchEngine.apply(state, event);
    }
    if (best.keys.toSet().containsAll({
          'bank-4-to-1',
          'bank-3-to-1',
          'bank-2-to-1',
          'standing-offer',
          'tactical-bandit',
          'tactical-governance',
          'tactical-invasion',
        }) &&
        seed > 20) {
      break;
    }
  }
  final manifest = <String, Object?>{};
  for (final entry in best.entries) {
    File(output.path + '/' + entry.key + '.code')
        .writeAsStringSync(entry.value.code);
    manifest[entry.key] = entry.value.info;
  }
  File(output.path + '/manifest.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(manifest));
}
