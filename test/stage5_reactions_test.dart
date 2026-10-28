import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

MatchState draft(int seed) {
  var s = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], seed);
  for (var i = 0; i < 6; i++) {
    s = MatchEngine.apply(s, PlaceVillage(MatchEngine.legalVertices(s).first));
    s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
  }
  return s;
}

MatchState grant(MatchState s, int player, Resource good, int amount) {
  expect(s.bank[good]!, greaterThanOrEqualTo(amount));
  final players = s.players.toList();
  final stores = Map<Resource, int>.of(players[player].stores);
  stores[good] = (stores[good] ?? 0) + amount;
  players[player] = players[player].copyWith(stores: stores);
  return s.copyWith(
    players: players,
    bank: {...s.bank, good: s.bank[good]! - amount},
  );
}

MatchState equip(MatchState s, int player, String id) {
  final card = StrategyCards.definitions.firstWhere((c) => c.id == id);
  final index = StrategyCards.deck(card.track).indexWhere((c) => c.id == id);
  final pile = s.drawPiles[card.track]!.toList();
  expect(pile.remove(index), isTrue);
  final players = s.players.toList();
  players[player] = players[player].copyWith(
    cards: [...players[player].cards, HeldCard(card.track, index)],
  );
  return s.copyWith(
    players: players,
    drawPiles: {...s.drawPiles, card.track: pile},
  );
}

void conserved(MatchState s) {
  for (final good in Resource.values) {
    final free = s.players.fold<int>(
      0,
      (sum, p) => sum + (p.stores[good] ?? 0),
    );
    final escrow = s.offers
        .where((o) => o.give == good)
        .fold<int>(0, (sum, o) => sum + o.giveCount);
    expect(free + escrow + s.bank[good]!, 19, reason: good.name);
    expect(s.bank[good], greaterThanOrEqualTo(0));
    for (final p in s.players) {
      expect(p.stores[good] ?? 0, greaterThanOrEqualTo(0));
    }
  }
}

MatchState rollOrResolve(MatchState s) {
  if (s.phase == MatchPhase.invasion) {
    while (s.tactical != null) {
      final w = s.tactical!;
      s = MatchEngine.apply(s, TimeoutTactical(w.id, w.responder));
    }
    s = MatchEngine.apply(s, const ResolveInvasion());
  }
  if (s.phase == MatchPhase.roll) {
    final pair = MatchEngine.expectedDice(s);
    s = MatchEngine.apply(s, RollDice(pair.$1, pair.$2));
  }
  if (s.phase == MatchPhase.bandit) {
    s = MatchEngine.apply(
      s,
      MoveBandit((s.banditTile + 1) % s.board.tiles.length),
    );
  }
  while (s.tactical != null) {
    final w = s.tactical!;
    s = MatchEngine.apply(s, TimeoutTactical(w.id, w.responder));
  }
  return s;
}

void main() {
  test(
    'standing escrow survives turns, accepts once, and replays end-to-end',
    () {
      MatchState? result;
      for (var seed = 1; seed < 300 && result == null; seed++) {
        var s = rollOrResolve(draft(seed));
        final gives = Resource.values
            .where((r) => (s.players[0].stores[r] ?? 0) > 0)
            .toList();
        final wants = Resource.values
            .where((r) => (s.players[1].stores[r] ?? 0) > 0)
            .toList();
        if (gives.isEmpty || wants.isEmpty) continue;
        final give = gives.first;
        final want = wants.where((r) => r != give).firstOrNull;
        if (want == null) continue;
        s = MatchEngine.apply(s, ProposeTrade(1, give, 1, want, 1));
        final id = s.offers.single.id;
        conserved(s);
        expect(s.players[0].stores[give] ?? 0, greaterThanOrEqualTo(0));
        expect(
          () => MatchEngine.apply(s, RespondTrade(1, true, offerId: id)),
          throwsStateError,
        ); // Not Ben's turn.
        s = MatchEngine.apply(s, const EndTurn());
        expect(s.active, 1);
        s = rollOrResolve(s);
        if ((s.players[1].stores[want] ?? 0) == 0) continue;
        final before = s.players[1].stores[give] ?? 0;
        s = MatchEngine.apply(s, RespondTrade(1, true, offerId: id));
        expect(s.players[1].stores[give], before + 1);
        expect(s.offers, isEmpty);
        expect(
          () => MatchEngine.apply(s, RespondTrade(1, true, offerId: id)),
          throwsStateError,
        );
        conserved(s);
        final restored = MatchEngine.importReplay(MatchEngine.exportReplay(s));
        expect(MatchEngine.snapshot(restored), MatchEngine.snapshot(s));
        result = s;
      }
      expect(result, isNotNull);
    },
  );

  test('counter replaces escrow once; expiration and withdrawal refund exactly once', () {
    var s = grant(
      grant(draft(88).copyWith(phase: MatchPhase.actions), 0, Resource.wood, 3),
      1,
      Resource.brick,
      3,
    );
    s = MatchEngine.apply(
      s,
      const ProposeTrade(1, Resource.wood, 2, Resource.brick, 1),
    );
    final original = s.offers.single;
    conserved(s);
    expect(
      () => MatchEngine.apply(
        s,
        const ProposeTrade(2, Resource.wood, 1, Resource.wool, 1),
      ),
      throwsStateError,
    );
    s = rollOrResolve(MatchEngine.apply(s, const EndTurn()));
    s = MatchEngine.apply(
      s,
      ProposeTrade(
        0,
        Resource.brick,
        2,
        Resource.wood,
        1,
        counterOf: original.id,
      ),
    );
    final counter = s.offers.single;
    expect(counter.isCounter, isTrue);
    expect(s.players[0].stores[Resource.wood] ?? 0, greaterThanOrEqualTo(2));
    expect(
      () => MatchEngine.apply(
        s,
        ProposeTrade(
          0,
          Resource.brick,
          1,
          Resource.wood,
          1,
          counterOf: counter.id,
        ),
      ),
      throwsStateError,
    );
    s = rollOrResolve(MatchEngine.apply(s, const EndTurn()));
    s = MatchEngine.apply(s, const EndTurn());
    expect(s.active, 0);
    s = rollOrResolve(s);
    s = MatchEngine.apply(s, RespondTrade(0, true, offerId: counter.id));
    conserved(s);
    expect(s.offers, isEmpty);

    s = MatchEngine.apply(
      s,
      const ProposeTrade(1, Resource.wood, 1, Resource.brick, 1),
    );
    final withdrawal = s.offers.single.id;
    s = MatchEngine.apply(s, WithdrawTrade(withdrawal));
    conserved(s);
    expect(
      () => MatchEngine.apply(s, WithdrawTrade(withdrawal)),
      throwsStateError,
    );

    s = MatchEngine.apply(
      s,
      const ProposeTrade(2, Resource.wood, 1, Resource.brick, 1),
    );
    s = rollOrResolve(MatchEngine.apply(s, const EndTurn()));
    s = rollOrResolve(MatchEngine.apply(s, const EndTurn()));
    s = MatchEngine.apply(s, const EndTurn());
    expect(s.active, 0);
    expect(s.offers, isEmpty);
    conserved(s);
  });

  test(
    'Bandit active Knight intercepts before theft; pass steals only once',
    () {
      var s = grant(
        draft(77).copyWith(phase: MatchPhase.bandit),
        1,
        Resource.ore,
        2,
      );
      final site = s.sites.entries.firstWhere((e) => e.value.owner == 1).key;
      final tile = s.topology.vertices[site].tiles.firstWhere(
        (v) => v != s.banditTile,
      );
      s = s.copyWith(
        knights: {
          1: const KnightPiece(1, KnightRank.sentinel, true, -1),
          2: const KnightPiece(1, KnightRank.warden, true, -1),
        },
      );
      final before = s.players[1].stores[Resource.ore]!;
      final handBefore = s.players[1].stores.values.fold<int>(
        0,
        (sum, n) => sum + n,
      );
      final open = MatchEngine.apply(s, MoveBandit(tile, victim: 1));
      expect(open.tactical?.kind, TacticalKind.bandit);
      expect(() => open.tactical!.responders.add(2), throwsUnsupportedError);
      expect(
        () => MatchEngine.apply(
          open,
          RespondTactical(open.tactical!.id + 1, 1, TacticalChoice.pass),
        ),
        throwsStateError,
      );
      expect(open.players[1].stores[Resource.ore], before);
      expect(() => MatchEngine.apply(open, const EndTurn()), throwsStateError);
      final intercepted = MatchEngine.apply(
        open,
        RespondTactical(open.tactical!.id, 1, TacticalChoice.intercept),
      );
      expect(intercepted.tactical, isNull);
      expect(intercepted.phase, MatchPhase.actions);
      expect(intercepted.players[1].stores[Resource.ore], before);
      expect(intercepted.knights[1]!.active, isFalse);
      expect(intercepted.reactionsUsed, contains(1));
      conserved(intercepted);

      expect(
        () =>
            MatchEngine.apply(open, TimeoutTactical(open.tactical!.id + 1, 1)),
        throwsStateError,
      );
      final passed = MatchEngine.apply(
        open,
        TimeoutTactical(open.tactical!.id, 1),
      );
      expect(
        passed.players[1].stores.values.fold<int>(0, (sum, n) => sum + n),
        handBefore - 1,
      );
      expect(passed.tactical, isNull);
      expect(passed.banditTile, tile);
      conserved(passed);
      expect(
        MatchEngine.snapshot(
          MatchEngine.apply(open, TimeoutTactical(open.tactical!.id, 1)),
        ),
        MatchEngine.snapshot(passed),
      );
    },
  );

  test(
    'matching Governance countercard cancels hostile card, not recursively',
    () {
      var s = grant(
        draft(109).copyWith(phase: MatchPhase.actions),
        1,
        Resource.ore,
        2,
      );
      s = equip(equip(s, 0, 'political-pressure'), 1, 'boundary-dispute');
      final attack = MatchEngine.legalCardPlays(
        s,
        0,
      ).firstWhere((e) => e.target == 1 && e.receive == Resource.ore);
      final open = MatchEngine.apply(s, attack);
      expect(open.tactical?.kind, TacticalKind.governance);
      expect(
        open.players[1].stores[Resource.ore],
        s.players[1].stores[Resource.ore],
      );
      expect(open.players[0].cards, hasLength(1));
      final blocked = MatchEngine.apply(
        open,
        RespondTactical(
          open.tactical!.id,
          1,
          TacticalChoice.counter,
          cardIndex: 0,
        ),
      );
      expect(blocked.tactical, isNull);
      expect(
        blocked.players[1].stores[Resource.ore],
        s.players[1].stores[Resource.ore],
      );
      expect(blocked.players[0].cards, isEmpty);
      expect(blocked.players[1].cards, isEmpty);
      expect(blocked.discardPiles[StrategyDeck.governance]!.length, 2);
      conserved(blocked);
      expect(
        () => MatchEngine.apply(
          blocked,
          RespondTactical(
            open.tactical!.id,
            1,
            TacticalChoice.counter,
            cardIndex: 0,
          ),
        ),
        throwsStateError,
      );
      final allowed = MatchEngine.apply(
        open,
        RespondTactical(open.tactical!.id, 1, TacticalChoice.pass),
      );
      expect(
        allowed.players[1].stores[Resource.ore],
        s.players[1].stores[Resource.ore]! - 1,
      );
      expect(
        allowed.players[0].stores[Resource.ore] ?? 0,
        (s.players[0].stores[Resource.ore] ?? 0) + 1,
      );
      conserved(allowed);
    },
  );

  test('invasion aid order, timeout, one response per round, clean reset', () {
    var s = draft(155).copyWith(
      phase: MatchPhase.actions,
      active: 2,
      reaverPressure: 2,
      reactionsUsed: {1, 2},
    );
    s = grant(grant(s, 1, Resource.ore, 1), 2, Resource.wheat, 1);
    s = MatchEngine.apply(s, const EndTurn());
    expect(s.round, 2);
    expect(s.active, 0);
    expect(s.phase, MatchPhase.invasion);
    expect(s.reactionsUsed, isEmpty);
    expect(s.tactical!.responders, [1, 2]);
    s = MatchEngine.apply(
      s,
      RespondTactical(
        s.tactical!.id,
        1,
        TacticalChoice.aid,
        good: Resource.ore,
      ),
    );
    expect(s.invasionAid, 2);
    expect(s.tactical!.responder, 2);
    s = MatchEngine.apply(s, TimeoutTactical(s.tactical!.id, 2));
    expect(s.tactical, isNull);
    expect(s.reactionsUsed, {1});
    expect(
      () => MatchEngine.apply(
        s,
        RespondTactical(0, 2, TacticalChoice.aid, good: Resource.wheat),
      ),
      throwsStateError,
    );
    s = MatchEngine.apply(s, const ResolveInvasion());
    expect(s.invasionAid, 0);
    expect(s.reaverPressure, 0);
    expect(s.phase, MatchPhase.roll);
    conserved(s);
  });

  test('adversarial seeded rounds never stall, duplicate goods, or diverge in replay', () {
    for (var seed = 0; seed < 35; seed++) {
      var s = draft(seed);
      for (var turn = 0; turn < 35 && s.phase != MatchPhase.finished; turn++) {
        s = rollOrResolve(s);
        if (s.phase == MatchPhase.actions) {
          s = MatchEngine.apply(s, const EndTurn());
        }
        conserved(s);
      }
      final replayed = MatchEngine.replay(
        [for (final p in s.players) p.id],
        s.seed,
        s.events,
      );
      expect(
        MatchEngine.snapshot(replayed),
        MatchEngine.snapshot(s),
        reason: 'seed $seed',
      );
    }
  });
}
