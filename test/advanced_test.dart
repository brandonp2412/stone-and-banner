import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

MatchState draft(int seed, [int seats = 3]) {
  var s = MatchEngine.newGame([
    for (var i = 0; i < seats; i++) 'Player ${i + 1}',
  ], seed);
  for (var i = 0; i < seats * 2; i++) {
    s = MatchEngine.apply(s, PlaceVillage(MatchEngine.legalVertices(s).first));
    s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
  }
  return s;
}

MatchState fund(MatchState s, int player, Map<Resource, int> goods) {
  final bank = Map<Resource, int>.of(s.bank);
  final players = s.players.toList();
  final store = Map<Resource, int>.of(players[player].stores);
  for (final entry in goods.entries) {
    expect(
      bank[entry.key]!,
      greaterThanOrEqualTo(entry.value),
      reason: 'Fixture bank stock for ${entry.key}',
    );
    bank[entry.key] = bank[entry.key]! - entry.value;
    store[entry.key] = (store[entry.key] ?? 0) + entry.value;
  }
  players[player] = players[player].copyWith(stores: store);
  return s.copyWith(players: players, bank: bank);
}

void conserved(MatchState s) {
  for (final r in Resource.values) {
    final total = s.players.fold<int>(0, (sum, p) => sum + (p.stores[r] ?? 0));
    expect(total + s.bank[r]!, MatchEngine.bankSupply, reason: r.name);
    expect(s.bank[r], greaterThanOrEqualTo(0));
    for (final p in s.players) {
      expect(p.stores[r] ?? 0, greaterThanOrEqualTo(0));
    }
  }
}

MatchState town(MatchState s, int vertex) {
  s = fund(s, s.active, MatchEngine.townCost);
  return MatchEngine.apply(s, UpgradeSite(vertex));
}

void main() {
  test('five named levels per track spend stock; Capital race paid once', () {
    var s = draft(55).copyWith(phase: MatchPhase.actions);
    final v = s.sites.keys.firstWhere((v) => s.sites[v]!.owner == 0);
    s = town(s, v);
    for (final track in StrategyDeck.values) {
      expect(track.tiers.length, 5);
      for (var level = 1; level <= 5; level++) {
        s = fund(s, 0, track.costFor(level));
        s = MatchEngine.apply(s, DevelopTown(track));
        expect(s.current.level(track), level);
        expect(
          () => MatchEngine.apply(s, DevelopTown(track)),
          throwsStateError,
          reason: 'Cannot skip cost or level',
        );
        conserved(s);
      }
      expect(MatchEngine.canDevelop(s, track), false);
    }
    s = fund(s, 0, MatchEngine.capitalCost);
    s = MatchEngine.apply(s, UpgradeSite(v));
    expect(s.sites[v]!.structure, Structure.capital);
    expect(s.firstCapitalOwner, 0);
    expect(s.current.charterPoints, 1);
    expect(MatchEngine.score(s, 0), greaterThanOrEqualTo(5));
    conserved(s);
    expect(
      MatchEngine.snapshot(
        MatchEngine.importReplay(MatchEngine.exportReplay(draft(55))),
      ),
      MatchEngine.snapshot(draft(55)),
    );
  });

  test(
    'Town replaces one basic yield with matching commodity; fifth tier two',
    () {
      for (final track in StrategyDeck.values) {
        MatchState? chosen;
        Resource? basic;
        for (var seed = 0; seed < 200; seed++) {
          final base = draft(seed);
          final number = MatchEngine.expectedDice(base);
          final value = number.$1 + number.$2;
          if (value == 7) continue;
          for (final entry in base.sites.entries) {
            if (entry.value.owner != 0) continue;
            if (base.topology.vertices[entry.key].tiles.any(
              (i) =>
                  i != base.banditTile &&
                  base.board.tiles[i].land == track.sourceLand &&
                  base.board.tiles[i].productionNumber == value,
            )) {
              chosen = base.copyWith(
                sites: {
                  ...base.sites,
                  entry.key: const Site(0, Structure.town),
                },
                players: [
                  base.players[0].copyWith(
                    buildings: [Structure.town, Structure.village],
                    developments: {track: 1},
                  ),
                  ...base.players.skip(1),
                ],
              );
              basic = track.sourceLand.produces;
              break;
            }
          }
          if (chosen != null) break;
        }
        expect(chosen, isNotNull, reason: track.name);
        final s = chosen!;
        final rolled = MatchEngine.roll(s);
        expect(
          rolled.players[0].stores[track.commodity] ?? 0,
          greaterThan(s.players[0].stores[track.commodity] ?? 0),
        );
        expect(
          rolled.players[0].stores[basic!] ?? 0,
          greaterThanOrEqualTo(s.players[0].stores[basic] ?? 0),
        );
        conserved(rolled);
        final players = s.players.toList();
        players[0] = players[0].copyWith(developments: {track: 5});
        final top = MatchEngine.roll(s.copyWith(players: players));
        expect(
          top.players[0].stores[track.commodity] ?? 0,
          greaterThanOrEqualTo(
            (rolled.players[0].stores[track.commodity] ?? 0) + 1,
          ),
        );
        conserved(top);
      }
    },
  );

  test('Knight recruit, activation, promotion, movement and displacement', () {
    var s = draft(76).copyWith(phase: MatchPhase.actions);
    final edgeId = s.roads.keys.firstWhere((e) => s.roads[e] == 0);
    final edge = s.topology.edges[edgeId];
    final from = edge.a, to = edge.b;
    s = fund(s, 0, MatchEngine.recruitCost);
    s = MatchEngine.apply(s, RecruitKnight(from));
    expect(s.knights[from]!.rank, KnightRank.sentinel);
    expect(s.knights[from]!.active, false);
    expect(() => MatchEngine.apply(s, ActivateKnight(from)), throwsStateError);
    s = fund(
      s.copyWith(turnSerial: s.turnSerial + 1),
      0,
      MatchEngine.activateCost,
    );
    s = MatchEngine.apply(s, ActivateKnight(from));
    expect(s.knights[from]!.active, true);
    expect(() => MatchEngine.apply(s, PromoteKnight(from)), throwsStateError);
    s = fund(
      s.copyWith(turnSerial: s.turnSerial + 1),
      0,
      MatchEngine.promotionCost(KnightRank.sentinel),
    );
    s = MatchEngine.apply(s, PromoteKnight(from));
    expect(s.knights[from]!.rank, KnightRank.warden);
    s = s.copyWith(
      turnSerial: s.turnSerial + 1,
      knights: {
        ...s.knights,
        to: const KnightPiece(1, KnightRank.sentinel, true, -1),
      },
    );
    expect(MatchEngine.legalMoveKnight(s, from, to), true);
    s = MatchEngine.apply(s, MoveKnight(from, to));
    expect(s.knights[to]!.owner, 0);
    expect(s.knights[from], isNull);
    expect(() => MatchEngine.apply(s, MoveKnight(to, from)), throwsStateError);
    conserved(s);
  });

  test(
    'failed Invasion uses shield once then scars Town; rebuilding discounted',
    () {
      var s = draft(91).copyWith(phase: MatchPhase.actions);
      final v = s.sites.keys.firstWhere((v) => s.sites[v]!.owner == 0);
      s = town(s, v);
      s = fund(s, 0, MatchEngine.fortCost);
      s = MatchEngine.apply(s, FortifyTown(v));
      expect(s.fortified, contains(v));
      s = s.copyWith(phase: MatchPhase.invasion, reaverPressure: 3);
      s = MatchEngine.apply(s, const ResolveInvasion());
      expect(s.fortified, isNot(contains(v)));
      expect(s.sites[v]!.structure, Structure.town);
      expect(s.invasions, 1);
      s = MatchEngine.apply(
        s.copyWith(phase: MatchPhase.invasion, reaverPressure: 3),
        const ResolveInvasion(),
      );
      expect(s.sites[v]!.structure, Structure.village);
      expect(s.reaverScars, contains(v));
      expect(() => MatchEngine.apply(s, UpgradeSite(v)), throwsStateError);
      s = fund(
        s.copyWith(phase: MatchPhase.actions),
        0,
        MatchEngine.rebuildCost,
      );
      s = MatchEngine.apply(s, UpgradeSite(v));
      expect(s.sites[v]!.structure, Structure.town);
      expect(s.reaverScars, isNot(contains(v)));
      conserved(s);
    },
  );

  test(
    'defence earns Honour only for sole Knight leader; victory scores 15',
    () {
      var s = draft(111).copyWith(
        phase: MatchPhase.invasion,
        reaverPressure: 3,
        knights: {
          0: const KnightPiece(0, KnightRank.champion, true, -1),
          1: const KnightPiece(0, KnightRank.warden, true, -1),
        },
      );
      expect(MatchEngine.defenceStrength(s), 5);
      s = MatchEngine.apply(s, const ResolveInvasion());
      expect(s.players[0].guardianHonour, 1);
      expect(s.phase, MatchPhase.roll);
      expect(
        () => MatchEngine.apply(s, const ResolveInvasion()),
        throwsStateError,
      );
      final players = s.players.toList();
      players[0] = players[0].copyWith(
        buildings: List.filled(4, Structure.capital),
        guardianHonour: 1,
      );
      final win = s.copyWith(players: players, phase: MatchPhase.finished);
      expect(MatchEngine.winner(win), 0);
      expect(MatchEngine.score(win, 0), greaterThanOrEqualTo(15));
      expect(() => MatchEngine.apply(win, const EndTurn()), throwsStateError);
      conserved(s);
    },
  );

  test(
    'bounded drought once per season and Supply Network never double pays',
    () {
      MatchState? selected;
      for (var seed = 0; seed < 200; seed++) {
        final s = draft(seed);
        if (MatchEngine.expectedDice(s).$1 + MatchEngine.expectedDice(s).$2 ==
            7) {
          continue;
        }
        final rolled = MatchEngine.roll(s);
        if (Resource.values.every(
          (r) =>
              (rolled.players[0].stores[r] ?? 0) ==
              (s.players[0].stores[r] ?? 0),
        )) {
          selected = s;
          break;
        }
      }
      expect(selected, isNotNull);
      var s = selected!;
      final players = s.players.toList();
      players[0] = players[0].copyWith(
        developments: {StrategyDeck.innovation: 4},
      );
      players[1] = players[1].copyWith(
        buildings: [Structure.capital, Structure.capital],
      );
      s = s.copyWith(players: players, dryRolls: {0: 1});
      final before = Resource.values.fold<int>(
        0,
        (sum, r) => sum + (s.players[0].stores[r] ?? 0),
      );
      final recovered = MatchEngine.roll(s);
      final after = Resource.values.fold<int>(
        0,
        (sum, r) => sum + (recovered.players[0].stores[r] ?? 0),
      );
      expect(after - before, 1);
      expect(recovered.reliefUsed, contains(0));
      final twice = MatchEngine.roll(
        recovered.copyWith(
          phase: MatchPhase.roll,
          rollCount: s.rollCount,
          dryRolls: {0: 3},
        ),
      );
      final newTotal = Resource.values.fold<int>(
        0,
        (sum, r) => sum + (twice.players[0].stores[r] ?? 0),
      );
      expect(newTotal - after, 0);
      conserved(twice);
    },
  );

  test('seeded full-match event log and export/import stay byte-identical', () {
    for (var seed = 10; seed < 35; seed++) {
      var s = draft(seed, seed.isEven ? 3 : 4);
      for (var turn = 0; turn < 72 && s.phase != MatchPhase.finished; turn++) {
        if (s.phase == MatchPhase.invasion) {
          s = MatchEngine.apply(s, const ResolveInvasion());
        }
        if (s.phase == MatchPhase.roll) s = MatchEngine.roll(s);
        if (s.phase == MatchPhase.bandit) {
          s = MatchEngine.apply(s, MoveBandit(s.banditTile == 0 ? 1 : 0));
        }
        if (s.phase == MatchPhase.actions) {
          final village = s.sites.keys
              .where(
                (v) =>
                    s.sites[v]!.owner == s.active &&
                    s.sites[v]!.structure == Structure.village,
              )
              .toList();
          if (village.isNotEmpty &&
              MatchEngine.legalUpgrade(s, village.first)) {
            s = MatchEngine.apply(s, UpgradeSite(village.first));
          }
          for (final track in StrategyDeck.values) {
            if (s.phase == MatchPhase.actions &&
                MatchEngine.canDevelop(s, track)) {
              s = MatchEngine.apply(s, DevelopTown(track));
            }
          }
          if (s.phase == MatchPhase.actions) {
            final possible = [
              for (var v = 0; v < s.topology.vertices.length; v++)
                if (MatchEngine.legalRecruit(s, v)) v,
            ];
            if (possible.isNotEmpty) {
              s = MatchEngine.apply(s, RecruitKnight(possible.first));
            }
          }
          if (s.phase == MatchPhase.actions) {
            s = MatchEngine.apply(s, const EndTurn());
          }
        }
        conserved(s);
        final replay = MatchEngine.importReplay(MatchEngine.exportReplay(s));
        expect(
          MatchEngine.snapshot(replay),
          MatchEngine.snapshot(s),
          reason: 'seed $seed turn $turn',
        );
      }
      expect(s.invasions, greaterThan(0));
    }
  });
  test('seven discards half only above protected hand capacity', () {
    MatchState? selected;
    for (var seed = 0; seed < 300; seed++) {
      final s = draft(seed);
      final dice = MatchEngine.expectedDice(s);
      if (dice.$1 + dice.$2 == 7) {
        selected = s;
        break;
      }
    }
    expect(selected, isNotNull);
    var s = selected!;
    final vertex = s.sites.keys.firstWhere((v) => s.sites[v]!.owner == 0);
    final total = Resource.values.fold<int>(
      0,
      (sum, r) => sum + (s.players[0].stores[r] ?? 0),
    );
    s = fund(s, 0, {Resource.wheat: 8 - total});
    final exposed = MatchEngine.roll(s);
    final protected = MatchEngine.roll(s.copyWith(fortified: {vertex}));
    int hand(MatchState state) => Resource.values.fold<int>(
      0,
      (sum, r) => sum + (state.players[0].stores[r] ?? 0),
    );
    expect(hand(exposed), 4);
    expect(hand(protected), 8);
    expect(exposed.reaverPressure, 1);
    conserved(exposed);
    conserved(protected);
  });

  test(
    'Stoneworks discount and Commerce bank benefits transfer real stock',
    () {
      var s = draft(234).copyWith(phase: MatchPhase.actions);
      final players = s.players.toList();
      players[0] = players[0].copyWith(
        developments: {StrategyDeck.innovation: 2, StrategyDeck.commerce: 5},
      );
      s = s.copyWith(players: players);
      expect(MatchEngine.effectiveRoadCost(s), {Resource.wood: 1});
      s = fund(s, 0, {Resource.wood: 3});
      final edge = MatchEngine.legalEdges(s).first;
      s = MatchEngine.apply(s, PlaceRoad(edge));
      final before = s.current.stores[Resource.brick] ?? 0;
      s = MatchEngine.apply(
        s,
        const BankExchange(Resource.wood, Resource.brick),
      );
      expect(s.current.stores[Resource.brick], before + 2);
      expect(MatchEngine.tradeRate(s, 0), 2);
      conserved(s);
    },
  );
}
