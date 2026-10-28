import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

MatchState draft(int seed, [int seats = 3]) {
  var s = MatchEngine.newGame([
    for (var i = 0; i < seats; i++) 'Seat ${i + 1}',
  ], seed);
  for (var n = 0; n < seats * 2; n++) {
    s = MatchEngine.apply(s, PlaceVillage(MatchEngine.legalVertices(s).first));
    s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
  }
  return s;
}

void conserved(MatchState s) {
  for (final r in Resource.values) {
    final held = s.players.fold<int>(0, (sum, p) => sum + (p.stores[r] ?? 0));
    expect(held + s.bank[r]!, 19, reason: r.name);
    expect(s.bank[r]!, greaterThanOrEqualTo(0));
    for (final p in s.players) {
      expect(p.stores[r] ?? 0, greaterThanOrEqualTo(0));
    }
  }
}

void main() {
  test('54 vertices, 72 edges, no split intersections', () {
    for (var seed = 0; seed < 25; seed++) {
      final g = BoardTopology(BoardGenerator.generate(seed));
      expect(g.vertices.length, 54);
      expect(g.edges.length, 72);
      expect(g.tileVertices.length, 19);
      expect(g.tileVertices.every((v) => v.length == 6), true);
      for (final v in g.vertices) {
        expect(v.edges.length, inInclusiveRange(2, 3));
        for (final id in v.edges) {
          expect([g.edges[id].a, g.edges[id].b], contains(v.id));
        }
      }
    }
  });

  test('3–4 seat snake drafts: spacing, two villages, two roads, replay', () {
    for (final count in [3, 4]) {
      final s = draft(20261027 + count, count);
      expect(s.phase, MatchPhase.roll);
      expect(s.active, 0);
      expect(s.sites.length, count * 2);
      expect(s.roads.length, count * 2);
      for (final v in s.sites.keys) {
        expect(s.topology.neighbours(v).any(s.sites.containsKey), false);
      }
      for (var i = 0; i < count; i++) {
        expect(s.sites.values.where((v) => v.owner == i).length, 2);
        expect(s.players[i].buildings, [Structure.village, Structure.village]);
      }
      conserved(s);
      expect(
        MatchEngine.snapshot(
          MatchEngine.replay(
            [for (final p in s.players) p.id],
            s.seed,
            s.events,
          ),
        ),
        MatchEngine.snapshot(s),
      );
    }
  });

  test(
    'roll event is seeded, production is not repeated and goods conserve',
    () {
      for (var seed = 0; seed < 30; seed++) {
        var s = draft(seed);
        final dice = MatchEngine.expectedDice(s);
        s = MatchEngine.roll(s);
        expect(s.dice, dice.$1 + dice.$2);
        expect(
          () => MatchEngine.apply(s, RollDice(dice.$1, dice.$2)),
          throwsStateError,
        );
        conserved(s);
        if (s.phase == MatchPhase.bandit) {
          s = MatchEngine.apply(s, MoveBandit(s.banditTile == 0 ? 1 : 0));
        }
        s = MatchEngine.apply(s, const EndTurn());
        conserved(s);
        expect(
          MatchEngine.snapshot(
            MatchEngine.replay(
              [for (final p in s.players) p.id],
              seed,
              s.events,
            ),
          ),
          MatchEngine.snapshot(s),
        );
      }
    },
  );

  test('illegal placements and costs cannot mutate match', () {
    final s = draft(45).copyWith(phase: MatchPhase.actions);
    final before = MatchEngine.snapshot(s);
    expect(
      () => MatchEngine.apply(s, const PlaceVillage(-1)),
      throwsStateError,
    );
    expect(() => MatchEngine.apply(s, const UpgradeSite(-1)), throwsStateError);
    expect(() => MatchEngine.apply(s, const PlaceRoad(-1)), throwsStateError);
    expect(MatchEngine.snapshot(s), before);
    conserved(s);
  });

  test('bank and consented player trades preserve supplies', () {
    var s = draft(200).copyWith(phase: MatchPhase.actions);
    final players = s.players.toList();
    final bank = Map<Resource, int>.of(s.bank);
    final first = Map<Resource, int>.of(players[0].stores);
    final second = Map<Resource, int>.of(players[1].stores);
    first[Resource.wood] = (first[Resource.wood] ?? 0) + 6;
    second[Resource.wool] = (second[Resource.wool] ?? 0) + 3;
    bank[Resource.wood] = bank[Resource.wood]! - 6;
    bank[Resource.wool] = bank[Resource.wool]! - 3;
    players[0] = players[0].copyWith(stores: first);
    players[1] = players[1].copyWith(stores: second);
    s = s.copyWith(players: players, bank: bank);
    conserved(s);
    s = MatchEngine.apply(s, const BankExchange(Resource.wood, Resource.brick));
    s = MatchEngine.apply(
      s,
      const ProposeTrade(1, Resource.wood, 2, Resource.wool, 2),
    );
    final firstOffer = s.offers.single.id;
    expect(
      () => MatchEngine.apply(s, const RespondTrade(2, true)),
      throwsStateError,
    );
    s = MatchEngine.apply(s, const EndTurn());
    final roll = MatchEngine.expectedDice(s);
    s = MatchEngine.apply(s, RollDice(roll.$1, roll.$2));
    if (s.phase == MatchPhase.bandit) {
      s = MatchEngine.apply(s, MoveBandit((s.banditTile + 1) % 19));
    }
    s = MatchEngine.apply(s, RespondTrade(1, true, offerId: firstOffer));
    conserved(s);
    expect(
      s.players[1].stores[Resource.wood],
      second[Resource.wood] == null ? 2 : second[Resource.wood]! + 2,
    );
    s = s.copyWith(active: 0, phase: MatchPhase.actions);
    s = MatchEngine.apply(
      s,
      const ProposeTrade(1, Resource.brick, 1, Resource.wool, 1),
    );
    final before = s.players[0].stores[Resource.brick] ?? 0;
    s = s.copyWith(active: 1, phase: MatchPhase.actions);
    s = MatchEngine.apply(
      s,
      RespondTrade(1, false, offerId: s.offers.single.id),
    );
    expect(s.players[0].stores[Resource.brick], before + 1);
    conserved(s);
  });

  test('opponent villages interrupt a five-edge road', () {
    final s = draft(311).copyWith(phase: MatchPhase.actions);
    final g = s.topology;
    List<int>? path;
    bool walk(int v, Set<int> used, List<int> edges) {
      if (edges.length == 5) {
        path = List.of(edges);
        return true;
      }
      for (final edge in g.vertices[v].edges) {
        if (used.contains(edge)) continue;
        final e = g.edges[edge];
        used.add(edge);
        edges.add(edge);
        if (walk(e.a == v ? e.b : e.a, used, edges)) return true;
        used.remove(edge);
        edges.removeLast();
      }
      return false;
    }

    walk(0, {}, []);
    expect(path, isNotNull);
    final own = s.copyWith(sites: {}, roads: {for (final e in path!) e: 0});
    expect(MatchEngine.longestRoad(own, 0), 5);
    final a = g.edges[path![0]], b = g.edges[path![1]];
    final shared = {a.a, a.b}.intersection({b.a, b.b}).single;
    final blocked = own.copyWith(
      sites: {shared: const Site(1, Structure.village)},
    );
    expect(MatchEngine.longestRoad(blocked, 0), lessThan(5));
  });

  test('15 VP wins with replacement structures', () {
    final s = draft(52);
    final players = s.players.toList();
    players[0] = players[0].copyWith(
      buildings: List.filled(4, Structure.capital),
    );
    final winning = s.copyWith(players: players);
    expect(MatchEngine.score(winning, 0), 16);
    expect(MatchEngine.winner(winning), 0);
  });

  test('portable replay round trip and tampered dice rejected', () {
    var s = draft(700);
    s = MatchEngine.roll(s);
    expect(
      MatchEngine.snapshot(
        MatchEngine.importReplay(MatchEngine.exportReplay(s)),
      ),
      MatchEngine.snapshot(s),
    );
    final modified = MatchEngine.exportReplay(s)
        .replaceFirst('"first":', '"first":999,"unused":');
    expect(() => MatchEngine.importReplay(modified), throwsStateError);
  });

  test('four seats replay 12 seeded turns identically', () {
    var s = draft(882, 4);
    for (var turn = 0; turn < 12; turn++) {
      s = MatchEngine.roll(s);
      if (s.phase == MatchPhase.bandit) {
        s = MatchEngine.apply(s, MoveBandit(s.banditTile == 0 ? 1 : 0));
      }
      s = MatchEngine.apply(s, const EndTurn());
      conserved(s);
    }
    expect(
      MatchEngine.snapshot(
        MatchEngine.replay([for (final p in s.players) p.id], s.seed, s.events),
      ),
      MatchEngine.snapshot(s),
    );
  });

  test('matching numbers pay exactly once and empty bank denies claims', () {
    MatchState? selected;
    Map<Resource, Map<int, int>>? expected;
    for (var seed = 0; seed < 150; seed++) {
      final s = draft(seed);
      final (a, b) = MatchEngine.expectedDice(s);
      final number = a + b;
      if (number == 7) continue;
      final claims = <Resource, Map<int, int>>{};
      for (var tile = 0; tile < s.board.tiles.length; tile++) {
        final hex = s.board.tiles[tile];
        if (hex.productionNumber != number || tile == s.banditTile) continue;
        final resource = hex.land.produces;
        if (resource == null) continue;
        for (final v in s.topology.tileVertices[tile]) {
          final site = s.sites[v];
          if (site == null) continue;
          final p = claims.putIfAbsent(resource, () => {});
          p[site.owner] = (p[site.owner] ?? 0) + 1;
        }
      }
      if (claims.isNotEmpty) {
        selected = s;
        expected = claims;
        break;
      }
    }
    expect(selected, isNotNull);
    final s = selected!;
    final rolled = MatchEngine.roll(s);
    for (final resource in Resource.values) {
      for (var player = 0; player < s.players.length; player++) {
        final before = s.players[player].stores[resource] ?? 0;
        final after = rolled.players[player].stores[resource] ?? 0;
        expect(after - before, expected?[resource]?[player] ?? 0);
      }
    }
    conserved(rolled);
    final scarce = expected!.keys.first;
    final bank = Map<Resource, int>.of(s.bank);
    final players = s.players.toList();
    final hand = Map<Resource, int>.of(players[0].stores);
    hand[scarce] = (hand[scarce] ?? 0) + bank[scarce]!;
    bank[scarce] = 0;
    players[0] = players[0].copyWith(stores: hand);
    final shortage = s.copyWith(players: players, bank: bank);
    final noGrant = MatchEngine.roll(shortage);
    for (var i = 0; i < players.length; i++) {
      expect(
        noGrant.players[i].stores[scarce] ?? 0,
        players[i].stores[scarce] ?? 0,
      );
    }
    conserved(noGrant);
  });

  test('fifth connected road earns longest-road bonus', () {
    var s = draft(312)
        .copyWith(phase: MatchPhase.actions, sites: {}, roads: {});
    final g = s.topology;
    List<int>? path;
    bool walk(int vertex, Set<int> used, List<int> result) {
      if (result.length == 5) {
        path = List.of(result);
        return true;
      }
      for (final edge in g.vertices[vertex].edges) {
        if (used.contains(edge)) continue;
        final e = g.edges[edge];
        used.add(edge);
        result.add(edge);
        if (walk(e.a == vertex ? e.b : e.a, used, result)) return true;
        used.remove(edge);
        result.removeLast();
      }
      return false;
    }

    walk(0, {}, []);
    final roads = {for (final edge in path!.take(4)) edge: 0};
    final players = s.players.toList();
    final goods = Map<Resource, int>.of(players[0].stores);
    final bank = Map<Resource, int>.of(s.bank);
    for (final resource in [Resource.wood, Resource.brick]) {
      goods[resource] = (goods[resource] ?? 0) + 1;
      bank[resource] = bank[resource]! - 1;
    }
    players[0] = players[0].copyWith(stores: goods);
    s = s.copyWith(roads: roads, players: players, bank: bank);
    expect(MatchEngine.legalRoad(s, path![4]), true);
    final before = MatchEngine.score(s, 0);
    s = MatchEngine.apply(s, PlaceRoad(path![4]));
    expect(s.longestRoadHolder, 0);
    expect(MatchEngine.score(s, 0), before + 2);
    conserved(s);
  });
}
