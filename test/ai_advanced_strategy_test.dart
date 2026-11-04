import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/match.dart';

const bot = HeuristicAi();

void conserved(MatchState state) {
  for (final good in Resource.values) {
    final total =
        (state.bank[good] ?? 0) +
        state.players.fold<int>(0, (sum, p) => sum + (p.stores[good] ?? 0)) +
        state.offers.fold<int>(
          0,
          (sum, o) => sum + (o.give == good ? o.giveCount : 0),
        );
    expect(total, MatchEngine.bankSupply, reason: good.name);
  }
}

MatchState deal(MatchState state, Map<Resource, int> goods, {int? seat}) {
  final index = seat ?? state.active;
  final prior = state.players[index].stores;
  final bank = Map<Resource, int>.of(state.bank);
  for (final good in Resource.values) {
    bank[good] = bank[good]! + (prior[good] ?? 0) - (goods[good] ?? 0);
    expect(bank[good], inInclusiveRange(0, MatchEngine.bankSupply));
  }
  final players = state.players.toList();
  players[index] = players[index].copyWith(stores: goods);
  return state.copyWith(players: players, bank: bank);
}

MatchState actions(int seed) {
  var state = MatchEngine.newGame(
    ['Ada', 'Ben', 'Cora'],
    seed,
    boardSeed: seed * 7 + 11,
  );
  for (var step = 0; step < 20 && state.phase != MatchPhase.roll; step++) {
    final seat = state.tactical?.responder ?? state.active;
    final view = AiActionAdapter.observe(state, seat);
    final choice = bot.choose(state)!;
    state = AiActionAdapter.applySelected(state, view, choice);
  }
  expect(state.phase, MatchPhase.roll);
  final view = AiActionAdapter.observe(state, state.active);
  state = AiActionAdapter.applySelected(state, view, bot.choose(state)!);
  if (state.phase == MatchPhase.bandit) {
    final banditView = AiActionAdapter.observe(state, state.active);
    state = AiActionAdapter.applySelected(
      state,
      banditView,
      bot.choose(state)!,
    );
  }
  expect(state.phase, MatchPhase.actions);
  conserved(state);
  return state;
}

MatchState town(int seed) {
  var state = deal(actions(seed), {Resource.wheat: 2, Resource.ore: 3});
  final vertex = state.sites.entries
      .firstWhere((e) => e.value.owner == state.active)
      .key;
  expect(MatchEngine.legalUpgrade(state, vertex), isTrue);
  state = MatchEngine.apply(state, UpgradeSite(vertex));
  conserved(state);
  return state;
}

void main() {
  test(
    'production signals respect own Town terrain and three-round season',
    () {
      final state = town(91).copyWith(round: 7);
      final view = AiActionAdapter.observe(state, state.active);
      expect(view.strategy.season, 2); // Harvest; no fictitious multiplier.
      for (final track in StrategyDeck.values) {
        var expected = 0;
        const pips = {
          2: 1,
          3: 2,
          4: 3,
          5: 4,
          6: 5,
          8: 5,
          9: 4,
          10: 3,
          11: 2,
          12: 1,
        };
        for (final e in state.sites.entries) {
          if (e.value.owner != state.active ||
              e.value.structure == Structure.village) {
            continue;
          }
          for (final tile in state.topology.vertices[e.key].tiles) {
            final hex = state.board.tiles[tile];
            if (tile != state.banditTile && hex.land == track.sourceLand) {
              expected += pips[hex.productionNumber] ?? 0;
            }
          }
        }
        expect(view.strategy.productionPips[track], expected);
      }
      expect(view.strategy.levels.values, everyElement(0));
    },
  );

  test('Town development chooses commodity output and discounted trade', () {
    var state = deal(town(47), {Resource.wheat: 1, Resource.ore: 1});
    final view = AiActionAdapter.observe(state, state.active);
    double outputValue(StrategyDeck track) =>
        4 +
        (view.strategy.productionPips[track] ?? 0) * 0.8 +
        (track == StrategyDeck.commerce ? 2 : 0);
    final bestTrack = StrategyDeck.values.reduce(
      (a, b) => outputValue(a) >= outputValue(b) ? a : b,
    );
    final first = AiActionAdapter.decide(view);
    expect(first, isA<DevelopTown>());
    expect((first! as DevelopTown).track, bestTrack);
    state = MatchEngine.apply(state, first);
    conserved(state);

    // Commerce II has an explicit bank-rate benefit independent of dice.
    final players = state.players.toList();
    players[state.active] = players[state.active].copyWith(
      developments: {StrategyDeck.commerce: 1},
    );
    state = deal(state.copyWith(players: players), {
      Resource.wheat: 1,
      Resource.ore: 2,
      Resource.cloth: 1,
    });
    final move = AiActionAdapter.decide(
      AiActionAdapter.observe(state, state.active),
    );
    expect(move, isA<DevelopTown>());
    expect((move! as DevelopTown).track, StrategyDeck.commerce);
    conserved(MatchEngine.apply(state, move));
  });

  test('capital resource goal outranks a second Town after first upgrade', () {
    final state = deal(town(157), {Resource.wood: 6});
    expect(
      state.sites.values
          .where((site) => site.owner == state.active)
          .map((site) => site.structure),
      containsAll([Structure.town, Structure.village]),
    );
    final view = AiActionAdapter.observe(state, state.active);
    final planned = AiActionAdapter.advancedDecision(view);
    expect(planned, isA<BankExchange>());
    // Capital needs wheat, ore and commodities, not another road resource.
    expect(
      MatchEngine.capitalCost.containsKey((planned! as BankExchange).receive),
      isTrue,
    );
    conserved(MatchEngine.apply(state, planned));
  });

  test('Reaver pressure activates and promotes Knights without free goods', () {
    var state = actions(101);
    final edge = state.roads.entries
        .firstWhere((e) => e.value == state.active)
        .key;
    final vertex = state.topology.edges[edge].a;
    state = deal(
      state.copyWith(
        reaverPressure: 2,
        knights: {
          vertex: KnightPiece(state.active, KnightRank.sentinel, false, -1),
        },
      ),
      {Resource.wheat: 1},
    );
    final activate = bot.choose(state);
    expect(activate, isA<ActivateKnight>());
    state = MatchEngine.apply(state, activate!);
    expect(state.knights[vertex]!.active, isTrue);
    conserved(state);

    state = deal(state.copyWith(turnSerial: state.turnSerial + 1), {
      Resource.ore: 1,
      Resource.wool: 1,
    });
    final promote = bot.choose(state);
    expect(promote, isA<PromoteKnight>());
    state = MatchEngine.apply(state, promote!);
    expect(state.knights[vertex]!.rank, KnightRank.warden);
    conserved(state);
  });

  test('fortification protects an owned Town under impending invasion', () {
    var state = deal(town(107), {
      Resource.brick: 2,
      Resource.coin: 1,
    }).copyWith(reaverPressure: 2);
    final choice = bot.choose(state);
    expect(choice, isA<FortifyTown>());
    state = MatchEngine.apply(state, choice!);
    expect(state.fortified, contains((choice as FortifyTown).vertex));
    conserved(state);
  });

  test('Knight movement only displaces a weaker public defender', () {
    var state = deal(actions(113), {});
    final edgeId = state.roads.entries
        .firstWhere((e) => e.value == state.active)
        .key;
    final edge = state.topology.edges[edgeId];
    final own = state.sites[edge.a]?.owner == state.active ? edge.a : edge.b;
    final rival = own == edge.a ? edge.b : edge.a;
    // The test edge is an owned initial road; its far side is unoccupied.
    expect(state.sites[rival], isNull);
    state = state.copyWith(
      knights: {
        own: KnightPiece(state.active, KnightRank.warden, true, -1),
        rival: const KnightPiece(1, KnightRank.sentinel, true, -1),
      },
    );
    final move = bot.choose(state);
    expect(move, isA<MoveKnight>());
    expect((move! as MoveKnight).to, rival);
    state = MatchEngine.apply(state, move);
    expect(state.knights[rival]!.owner, state.active);
    conserved(state);
  });

  test('invasion aid uses public gap and passes when victory impossible', () {
    var state = actions(127);
    state = deal(state, {Resource.wheat: 1, Resource.ore: 1}, seat: 1);
    MatchState invasion(int aid) => state.copyWith(
      phase: MatchPhase.invasion,
      reaverPressure: 3,
      invasionAid: aid,
      tactical: TacticalWindow(
        state.events.length,
        TacticalKind.invasion,
        state.active,
        [1],
      ),
    );
    final two = invasion(2);
    final ore = AiActionAdapter.decide(AiActionAdapter.observe(two, 1));
    expect(ore, isA<RespondTactical>());
    expect((ore! as RespondTactical).good, Resource.ore);
    conserved(MatchEngine.apply(two, ore));
    final wheatOnly = deal(two, {Resource.wheat: 1}, seat: 1);
    final cannotBridge = AiActionAdapter.decide(
      AiActionAdapter.observe(wheatOnly, 1),
    );
    expect((cannotBridge! as RespondTactical).choice, TacticalChoice.pass);
    final one = invasion(3);
    final wheat = AiActionAdapter.decide(AiActionAdapter.observe(one, 1));
    expect((wheat! as RespondTactical).good, Resource.wheat);
    final hopeless = invasion(0);
    final pass = AiActionAdapter.decide(AiActionAdapter.observe(hopeless, 1));
    expect((pass! as RespondTactical).choice, TacticalChoice.pass);
  });

  test('catch-up 3:1 and exhausted bank remain finite and legal', () {
    var state = actions(131);
    final players = state.players.toList();
    players[1] = players[1].copyWith(charterPoints: 4);
    state = deal(state.copyWith(players: players), {Resource.wood: 3});
    final view = AiActionAdapter.observe(state, state.active);
    expect(view.strategy.scoreDeficit, greaterThanOrEqualTo(3));
    expect(view.strategy.tradeRate, 3);
    final trade = AiActionAdapter.decide(view);
    expect(trade, isA<BankExchange>());
    expect((trade! as BankExchange).receive, Resource.ore);
    state = MatchEngine.apply(state, trade);
    expect(state.catchupUsed, contains(state.active));
    conserved(state);

    // Deplete ore entirely into another hand, preserving the total stock.
    final depleted = deal(state, {
      ...state.players[1].stores,
      Resource.ore:
          (state.players[1].stores[Resource.ore] ?? 0) +
          (state.bank[Resource.ore] ?? 0),
    }, seat: 1);
    expect(depleted.bank[Resource.ore], 0);
    expect(
      AiActionAdapter.observe(depleted, depleted.active).legalActions
          .whereType<BankExchange>()
          .where((e) => e.receive == Resource.ore),
      isEmpty,
    );
    conserved(depleted);
  });

  test('drought recovery favours Aqueduct but never mints relief directly', () {
    var state = town(139);
    final players = state.players.toList();
    players[state.active] = players[state.active].copyWith(
      developments: {StrategyDeck.innovation: 2},
    );
    players[1] = players[1].copyWith(charterPoints: 4);
    state = deal(
      state.copyWith(players: players, dryRolls: {state.active: 1}),
      {Resource.wheat: 1, Resource.ore: 2, Resource.paper: 2},
    );
    final beforeBank = Map<Resource, int>.of(state.bank);
    final move = AiActionAdapter.decide(
      AiActionAdapter.observe(state, state.active),
    );
    expect(move, isA<DevelopTown>());
    expect((move! as DevelopTown).track, StrategyDeck.innovation);
    state = MatchEngine.apply(state, move);
    expect(state.current.level(StrategyDeck.innovation), 3);
    expect(state.reliefUsed, isEmpty);
    expect(state.bank[Resource.wheat], beforeBank[Resource.wheat]! + 1);
    conserved(state);
  });

  test('decision cap forces End Turn and finished games stay terminal', () {
    final state = actions(149);
    final capped = state.copyWith(
      events: [
        ...state.events,
        for (var i = 0; i < 8; i++) const DiscardStrategyCard(0),
      ],
    );
    final view = AiActionAdapter.observe(capped, capped.active);
    expect(view.actionsSinceRoll, 8);
    expect(AiActionAdapter.decide(view), isA<EndTurn>());
    expect(bot.choose(capped), isA<EndTurn>());
    final finished = state.copyWith(phase: MatchPhase.finished);
    expect(
      AiActionAdapter.decide(
        AiActionAdapter.observe(finished, finished.active),
      ),
      isNull,
    );
    expect(bot.choose(finished), isNull);
  });

  test('advanced choices ignore rivals hidden stores and cards', () {
    final state = deal(town(151), {
      Resource.wheat: 1,
      Resource.ore: 1,
    }).copyWith(reaverPressure: 2);
    final baselineView = AiActionAdapter.observe(state, state.active);
    final baseline = AiActionAdapter.advancedDecision(baselineView);
    final players = state.players.toList();
    for (var i = 0; i < players.length; i++) {
      if (i == state.active) continue;
      players[i] = players[i].copyWith(
        stores: {Resource.coin: 18 - i},
        cards: const [],
      );
    }
    final altered = state.copyWith(players: players);
    final view = AiActionAdapter.observe(altered, state.active);
    expect(view.strategy.bankStock, baselineView.strategy.bankStock);
    expect(
      AiActionAdapter.advancedDecision(view)?.toJson(),
      baseline?.toJson(),
    );
    expect(bot.choose(altered)?.toJson(), bot.choose(state)?.toJson());
  });

  test(
    'multi-round offline events are deterministic, bounded and replayable',
    () {
      String runSeed(int seed) {
        var state = MatchEngine.newGame(
          ['Ada', 'Ben', 'Cora'],
          seed,
          boardSeed: seed * 13,
        );
        for (
          var i = 0;
          i < 1000 && state.round < 9 && state.phase != MatchPhase.finished;
          i++
        ) {
          final seat = state.tactical?.responder ?? state.active;
          final view = AiActionAdapter.observe(state, seat);
          final action = bot.choose(state);
          expect(action, isNotNull);
          state = AiActionAdapter.applySelected(state, view, action!);
          conserved(state);
        }
        expect(state.round >= 9 || state.phase == MatchPhase.finished, isTrue);
        final encoded = MatchEngine.exportReplay(state);
        final restored = MatchEngine.importReplay(encoded);
        expect(MatchEngine.snapshot(restored), MatchEngine.snapshot(state));
        return encoded;
      }

      for (final seed in [61, 83, 197]) {
        expect(runSeed(seed), runSeed(seed));
      }
    },
  );
}
