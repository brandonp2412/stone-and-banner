import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/match.dart';

void conserved(MatchState state) {
  for (final resource in Resource.values) {
    final total =
        (state.bank[resource] ?? 0) +
        state.players.fold<int>(
          0,
          (sum, player) => sum + (player.stores[resource] ?? 0),
        ) +
        state.offers.fold<int>(
          0,
          (sum, offer) => sum + (offer.give == resource ? offer.giveCount : 0),
        );
    expect(total, MatchEngine.bankSupply, reason: resource.name);
  }
}

MatchState deal(MatchState state, Map<Resource, int> goods) {
  final existing = state.current.stores;
  final bank = Map<Resource, int>.of(state.bank);
  for (final resource in Resource.values) {
    bank[resource] =
        bank[resource]! + (existing[resource] ?? 0) - (goods[resource] ?? 0);
    expect(bank[resource], greaterThanOrEqualTo(0));
  }
  final players = state.players.toList();
  players[state.active] = state.current.copyWith(stores: goods);
  return state.copyWith(players: players, bank: bank);
}

MatchState afterDraft(int seed) {
  const ai = HeuristicAi();
  var state = MatchEngine.newGame(
    ['Ada', 'Ben', 'Cora'],
    seed,
    boardSeed: seed * 7 + 11,
  );
  for (var i = 0; i < 12 && state.phase != MatchPhase.roll; i++) {
    final event = ai.choose(state);
    expect(event, isNotNull);
    final view = AiActionAdapter.observe(state, state.active);
    state = AiActionAdapter.applySelected(state, view, event!);
  }
  expect(state.phase, MatchPhase.roll);
  return state;
}

int productivePips(MatchState state, int player) {
  const pips = {2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 8: 5, 9: 4, 10: 3, 11: 2, 12: 1};
  var total = 0;
  for (final entry in state.sites.entries) {
    if (entry.value.owner != player) continue;
    for (final tile in state.topology.vertices[entry.key].tiles) {
      total += pips[state.board.tiles[tile].productionNumber] ?? 0;
    }
  }
  return total;
}

MatchState randomDraft(int seed) {
  final rng = math.Random(seed ^ 0x13579);
  var state = MatchEngine.newGame(
    ['Ada', 'Ben', 'Cora'],
    seed,
    boardSeed: seed * 7 + 11,
  );
  while (state.phase != MatchPhase.roll) {
    final legal = AiLegalActions(state);
    final choices = state.phase == MatchPhase.setupVillage
        ? legal.villages
        : legal.roads;
    state = MatchEngine.apply(state, choices[rng.nextInt(choices.length)]);
  }
  return state;
}

void main() {
  test('snake draft chooses legal spaced production and is replayable', () {
    for (final seed in [3, 17, 42, 103, 311]) {
      final state = afterDraft(seed);
      expect(state.sites.length, 6);
      expect(state.roads.length, 6);
      expect(state.sites.values.where((s) => s.owner == 0).length, 2);
      for (final vertex in state.sites.keys) {
        for (final neighbour in state.topology.neighbours(vertex)) {
          expect(state.sites.containsKey(neighbour), isFalse);
        }
      }
      conserved(state);
      final replay = MatchEngine.importReplay(MatchEngine.exportReplay(state));
      expect(MatchEngine.snapshot(replay), MatchEngine.snapshot(state));
    }
  });

  test('fixed seeded boards beat random legal draft in expected output', () {
    final seeds = [3, 17, 42, 103, 311, 509, 719, 1009, 1301, 2027];
    var aiPips = 0;
    var randomPips = 0;
    var aiBetter = 0;
    for (final seed in seeds) {
      final ai = afterDraft(seed);
      final random = randomDraft(seed);
      for (var seat = 0; seat < 3; seat++) {
        aiPips += productivePips(ai, seat);
        randomPips += productivePips(random, seat);
        if (productivePips(ai, seat) > productivePips(random, seat)) {
          aiBetter++;
        }
      }
    }
    // This measures draft production, not overall match win probability.
    expect(aiPips, greaterThan(randomPips));
    expect(aiBetter, greaterThan(15));
  });

  test('prioritizes legal VP upgrades and conserves stores', () {
    const ai = HeuristicAi();
    var state = afterDraft(117);
    final (first, second) = MatchEngine.expectedDice(state);
    state = MatchEngine.apply(state, RollDice(first, second));
    if (state.phase == MatchPhase.bandit) {
      state = MatchEngine.apply(state, ai.choose(state)!);
    }
    expect(state.phase, MatchPhase.actions);
    final upgraded = deal(state, {Resource.wheat: 2, Resource.ore: 3});
    final move = ai.choose(upgraded);
    expect(move, isA<UpgradeSite>());
    expect(
      MatchEngine.legalUpgrades(upgraded),
      contains((move as UpgradeSite).vertex),
    );
    final next = MatchEngine.apply(upgraded, move);
    expect(
      MatchEngine.score(next, next.active),
      MatchEngine.score(upgraded, upgraded.active) + 1,
    );
    conserved(next);

    final capitalStock = deal(next, {
      Resource.wheat: 2,
      Resource.ore: 2,
      Resource.paper: 1,
      Resource.cloth: 1,
      Resource.coin: 1,
    });
    final capitalMove = ai.choose(capitalStock);
    expect(capitalMove, isA<UpgradeSite>());
    final capital = MatchEngine.apply(capitalStock, capitalMove!);
    expect(
      MatchEngine.score(capital, capital.active),
      MatchEngine.score(capitalStock, capitalStock.active) + 3,
    );
    conserved(capital);

    // No resource exchange may liquidate the only wood/brick required for
    // a future village; 3 wood is below normal 4:1 exchange rate.
    final saving = deal(state, {Resource.wood: 3});
    final saveMove = ai.choose(saving);
    expect(saveMove, isNot(isA<BankExchange>()));
    conserved(saving);
  });

  test('bank exchange spends surplus toward a construction deficit', () {
    const ai = HeuristicAi();
    var state = afterDraft(251);
    final (first, second) = MatchEngine.expectedDice(state);
    state = MatchEngine.apply(state, RollDice(first, second));
    if (state.phase == MatchPhase.bandit) {
      state = MatchEngine.apply(state, ai.choose(state)!);
    }
    // Existing early villages need wheat/ore to upgrade. No free resources
    // are introduced: both the fixture and the move conserve bank stock.
    final stocked = deal(state, {Resource.wood: 6});
    final move = ai.choose(stocked);
    expect(move, isA<BankExchange>());
    final exchange = move! as BankExchange;
    expect(exchange.give, Resource.wood);
    expect(exchange.receive, Resource.ore);
    final after = MatchEngine.apply(stocked, exchange);
    expect(after.current.stores[Resource.wood], 2);
    expect(after.current.stores[Resource.ore], 1);
    expect(
      MatchEngine.score(after, after.active),
      MatchEngine.score(stocked, stocked.active),
    );
    conserved(after);
  });

  test('choices ignore other seats private inventories in action phase', () {
    const ai = HeuristicAi();
    var state = afterDraft(53);
    final (a, b) = MatchEngine.expectedDice(state);
    state = MatchEngine.apply(state, RollDice(a, b));
    if (state.phase == MatchPhase.bandit) {
      state = MatchEngine.apply(state, ai.choose(state)!);
    }
    final first = ai.choose(state)!;
    final players = state.players.toList();
    players[1] = players[1].copyWith(stores: {Resource.coin: 9});
    players[2] = players[2].copyWith(stores: {Resource.wheat: 8});
    final altered = state.copyWith(players: players);
    expect(ai.choose(altered)!.toJson(), first.toJson());
  });

  test('Bandit scores public sites without learning who has hidden goods', () {
    const ai = HeuristicAi();
    final state = afterDraft(83).copyWith(phase: MatchPhase.bandit);
    final move = ai.choose(state)! as MoveBandit;
    expect(move.victim, isNull);
    final players = state.players.toList();
    players[1] = players[1].copyWith(stores: {Resource.wool: 18});
    players[2] = players[2].copyWith(stores: {});
    final hiddenChange = state.copyWith(players: players);
    expect(ai.choose(hiddenChange)!.toJson(), move.toJson());
    final view = AiActionAdapter.observe(state, state.active);
    expect(
      () => AiActionAdapter.applySelected(state, view, move),
      returnsNormally,
    );
  });

  test('bounded multi-round deterministic bot applies only reducer events', () {
    const ai = HeuristicAi();
    for (final seed in [71, 72, 73]) {
      var state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], seed);
      for (
        var i = 0;
        i < 350 && state.round < 8 && state.phase != MatchPhase.finished;
        i++
      ) {
        final event = ai.choose(state);
        expect(event, isNotNull);
        final actor = state.tactical?.responder ?? state.active;
        final view = AiActionAdapter.observe(state, actor);
        state = AiActionAdapter.applySelected(state, view, event!);
        conserved(state);
      }
      expect(state.round, greaterThanOrEqualTo(5));
      final again = MatchEngine.importReplay(MatchEngine.exportReplay(state));
      expect(MatchEngine.snapshot(again), MatchEngine.snapshot(state));
    }
  });
}
