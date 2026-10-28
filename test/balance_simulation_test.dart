import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/balance.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/simulation.dart';

void expectConserved(MatchState s) {
  for (final good in Resource.values) {
    final total =
        (s.bank[good] ?? 0) +
        s.players.fold<int>(0, (n, p) => n + (p.stores[good] ?? 0)) +
        s.offers.fold<int>(0, (n, o) => n + (o.give == good ? o.giveCount : 0));
    expect(total, MatchEngine.bankSupply, reason: good.name);
    expect(s.bank[good], greaterThanOrEqualTo(0));
    for (final p in s.players) {
      expect(p.stores[good] ?? 0, greaterThanOrEqualTo(0));
    }
  }
}

void main() {
  test('baseline rules retain old replay compatibility', () {
    final s = MatchEngine.newGame(['A', 'B', 'C'], 123);
    expect(s.balance.catchupRate, 3);
    final payload =
        jsonDecode(MatchEngine.exportReplay(s)) as Map<String, dynamic>;
    payload.remove('balance'); // Historical v1 fixtures have no policy field.
    final imported = MatchEngine.importReplay(jsonEncode(payload));
    expect(imported.balance.toJson(), MatchBalance.baseline.toJson());
    expectConserved(imported);
  });

  test('malformed experimental rules are rejected on replay import', () {
    final payload = jsonDecode(
      MatchEngine.exportReplay(MatchEngine.newGame(['A', 'B', 'C'], 9)),
    ) as Map<String, dynamic>;
    (payload['balance'] as Map<String, dynamic>)['marketRate'] = 0;
    expect(
      () => MatchEngine.importReplay(jsonEncode(payload)),
      throwsFormatException,
    );
  });

  test('trailing trade enhancement spends goods, gives no VP', () {
    final baseline = MatchEngine.newGame(['A', 'B', 'C'], 123);
    final players = baseline.players.toList();
    players[0] = players[0].copyWith(
      buildings: [Structure.capital, Structure.town],
    );
    players[1] = players[1].copyWith(
      buildings: [Structure.village],
      stores: {Resource.wood: 4},
    );
    final b = baseline.copyWith(
      phase: MatchPhase.actions,
      active: 1,
      players: players,
      bank: {...baseline.bank, Resource.wood: 15},
    );
    final e =
        MatchEngine.newGame(
          ['A', 'B', 'C'],
          123,
          balance: MatchBalance.enhancedTrade,
        ).copyWith(
          phase: MatchPhase.actions,
          active: 1,
          players: players,
          bank: {...baseline.bank, Resource.wood: 15},
        );
    expect(MatchEngine.tradeRate(b, 1), 3);
    expect(MatchEngine.tradeRate(e, 1), 2);
    final before = MatchEngine.score(e, 1);
    final after = MatchEngine.apply(
      e,
      const BankExchange(Resource.wood, Resource.ore),
    );
    expect(MatchEngine.score(after, 1), before);
    expect(after.current.stores[Resource.wood], 2);
    expect(after.current.stores[Resource.ore], 1);
    expect(after.catchupUsed, contains(1));
    expectConserved(after);
  });

  test('seeded bot matches are replayable and conserved across boards', () {
    for (final seed in [103, 104, 105, 106]) {
      final result = BalanceSimulation.run(
        seed: seed,
        maxRounds: 16,
        seats: seed.isEven ? 4 : 3,
      );
      expect(result.state.events, isNotEmpty);
      expect(result.state.round, lessThanOrEqualTo(17));
      expect(
        result.reactionUses,
        lessThanOrEqualTo(result.reactionOpportunities),
      );
      expectConserved(result.state);
      var step = MatchEngine.newGame(
        [for (final player in result.state.players) player.id],
        result.state.seed,
        boardSeed: result.state.board.seed,
        balance: result.state.balance,
      );
      for (final event in result.state.events) {
        step = MatchEngine.apply(step, event);
        expectConserved(step);
      }
      expect(MatchEngine.snapshot(step), MatchEngine.snapshot(result.state));
      final replay = MatchEngine.importReplay(
        MatchEngine.exportReplay(result.state),
      );
      expect(MatchEngine.snapshot(replay), MatchEngine.snapshot(result.state));
    }
  });

  test(
    'rule variants deterministic with identical seeds and replay policy',
    () {
      for (final rules in [
        MatchBalance.baseline,
        MatchBalance.enhancedTrade,
        MatchBalance.earlierRelief,
        MatchBalance.slowerStoneworks,
        MatchBalance.cheaperStoneworks,
        MatchBalance.slowerMarket,
        MatchBalance.slowerGuild,
        MatchBalance.weakerBazaar,
      ]) {
        final first = BalanceSimulation.run(
          seed: 209,
          balance: rules,
          maxRounds: 12,
        );
        final second = BalanceSimulation.run(
          seed: 209,
          balance: rules,
          maxRounds: 12,
        );
        expect(
          MatchEngine.snapshot(first.state),
          MatchEngine.snapshot(second.state),
        );
        expect(first.unproductiveRounds, second.unproductiveRounds);
        final replay = MatchEngine.importReplay(
          MatchEngine.exportReplay(first.state),
        );
        expect(replay.balance.toJson(), rules.toJson());
        expect(MatchEngine.snapshot(replay), MatchEngine.snapshot(first.state));
        expectConserved(replay);
      }
    },
  );
}
