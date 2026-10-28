import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

MatchState prepared() {
  var s = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 321);
  for (var i = 0; i < 6; i++) {
    s = MatchEngine.apply(s, PlaceVillage(MatchEngine.legalVertices(s).first));
    s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
  }
  final bank = Map<Resource, int>.of(s.bank);
  final players = s.players.toList();
  for (var i = 0; i < 2; i++) {
    final stores = Map<Resource, int>.of(players[i].stores);
    for (final resource in Resource.values) {
      final number = i == 0 ? 5 : 2;
      bank[resource] = bank[resource]! - number;
      stores[resource] = (stores[resource] ?? 0) + number;
    }
    players[i] = players[i].copyWith(stores: stores);
  }
  final mine = s.sites.keys.firstWhere((v) => s.sites[v]!.owner == 0);
  final villages = {...s.sites, mine: const Site(0, Structure.town)};
  final knights = <int, KnightPiece>{
    mine: const KnightPiece(0, KnightRank.sentinel, false, -1),
    s.sites.keys.firstWhere((v) => s.sites[v]!.owner == 0 && v != mine):
        const KnightPiece(0, KnightRank.warden, true, -1),
    s.sites.keys.firstWhere((v) => s.sites[v]!.owner == 1): const KnightPiece(
      1,
      KnightRank.sentinel,
      true,
      -1,
    ),
  };
  return s.copyWith(
    phase: MatchPhase.actions,
    players: players,
    bank: bank,
    sites: villages,
    knights: knights,
  );
}

MatchState holding(MatchState s, StrategyCard definition) {
  final track = definition.track;
  final index = StrategyCards.deck(track)
      .indexWhere((c) => c.id == definition.id);
  final draw = List<int>.of(s.drawPiles[track]!);
  expect(draw.remove(index), isTrue);
  final players = s.players.toList();
  players[s.active] = s.current.copyWith(
    cards: [...s.current.cards, HeldCard(track, index)],
  );
  return s.copyWith(players: players, drawPiles: {...s.drawPiles, track: draw});
}

void checkConservation(MatchState s) {
  for (final good in Resource.values) {
    expect(
      (s.bank[good] ?? 0) +
          s.players.fold<int>(0, (total, p) => total + (p.stores[good] ?? 0)),
      MatchEngine.bankSupply,
      reason: 'Conservation of ${good.name}',
    );
    expect(s.bank[good], greaterThanOrEqualTo(0));
  }
}

void checkCards(MatchState s) {
  for (final track in StrategyDeck.values) {
    final indices = <int>[
      ...s.drawPiles[track]!,
      ...s.discardPiles[track]!,
      for (final p in s.players)
        for (final c in p.cards)
          if (c.track == track) c.index,
    ]..sort();
    expect(
      indices,
      List.generate(StrategyCards.deck(track).length, (i) => i),
      reason: 'Every physical ${track.name} copy accounted for',
    );
  }
}

void main() {
  test('three original decks contain exactly 18 physical cards each', () {
    expect(StrategyCards.definitions.length, 28);
    final unique = StrategyCards.definitions.map((c) => c.id).toSet();
    expect(unique.length, StrategyCards.definitions.length);
    for (final track in StrategyDeck.values) {
      expect(StrategyCards.deck(track), hasLength(18));
      expect(StrategyCards.deck(track).every((c) => c.track == track), isTrue);
    }
    checkCards(MatchEngine.newGame(['A', 'B', 'C'], 100));
  });

  test('every defined effect has a legal target, consumes exactly one card, '
      'and conserves all goods and copies', () {
    final initial = prepared();
    checkConservation(initial);
    for (final card in StrategyCards.definitions) {
      final s = holding(initial, card);
      final options = MatchEngine.legalCardPlays(s, 0);
      expect(options, isNotEmpty, reason: card.name);
      final next = MatchEngine.apply(s, options.first);
      expect(next.current.cards, isEmpty, reason: card.name);
      expect(next.discardPiles[card.track], hasLength(1), reason: card.name);
      expect(next.events.last, isA<PlayStrategyCard>());
      checkConservation(next);
      checkCards(next);
      expect(() => MatchEngine.apply(next, options.first), throwsStateError);
      // Playing a chosen card is deterministic when reduced from the same state.
      expect(
        MatchEngine.snapshot(next),
        MatchEngine.snapshot(MatchEngine.apply(s, options.first)),
      );
    }
  });

  test('invalid targets never mutate state or consume a card', () {
    final s = holding(prepared(), StrategyCards.definitions.first);
    final before = MatchEngine.snapshot(s);
    expect(
      () => MatchEngine.apply(
        s,
        const PlayStrategyCard(0, receive: Resource.coin),
      ),
      throwsStateError,
    );
    expect(
      () => MatchEngine.apply(s, const PlayStrategyCard(1)),
      throwsStateError,
    );
    expect(MatchEngine.snapshot(s), before);
  });

  test('cards may always be discarded and cannot block ending a turn', () {
    final s = holding(prepared(), StrategyCards.definitions.first);
    final next = MatchEngine.apply(s, const DiscardStrategyCard(0));
    expect(next.current.cards, isEmpty);
    checkCards(next);
    expect(MatchEngine.apply(next, const EndTurn()).phase, MatchPhase.roll);
  });

  test('hand limit skips acquisition without removing physical copies', () {
    var s = prepared();
    final players = s.players.toList();
    final cards = <HeldCard>[];
    final pile = List<int>.of(s.drawPiles[StrategyDeck.innovation]!);
    for (var i = 0; i < StrategyCards.handLimit; i++) {
      cards.add(HeldCard(StrategyDeck.innovation, pile.removeLast()));
    }
    players[0] = players[0].copyWith(
      cards: cards,
      developments: {for (final t in StrategyDeck.values) t: 5},
    );
    s = s.copyWith(
      phase: MatchPhase.roll,
      players: players,
      drawPiles: {...s.drawPiles, StrategyDeck.innovation: pile},
    );
    final before = s.drawPiles.map((k, v) => MapEntry(k, List<int>.of(v)));
    final next = MatchEngine.roll(s);
    expect(next.current.cards, hasLength(StrategyCards.handLimit));
    expect(next.drawPiles, before);
    checkCards(next);
    checkConservation(next);
    if (next.phase == MatchPhase.actions) {
      expect(() => MatchEngine.apply(next, const EndTurn()), returnsNormally);
    }
  });

  test(
    'each qualified seat draws on the same event without card-name leaks',
    () {
      var s = prepared();
      final players = [
        for (final p in s.players)
          p.copyWith(developments: {for (final t in StrategyDeck.values) t: 5}),
      ];
      s = s.copyWith(players: players, phase: MatchPhase.roll);
      for (var n = 0; n < 100; n++) {
        final candidate = s.copyWith(rollCount: n);
        if (MatchEngine.strategyRoll(candidate.copyWith(rollCount: n + 1)).$1 <=
            3) {
          s = candidate;
          break;
        }
      }
      final next = MatchEngine.roll(s);
      final track = StrategyDeck.values[MatchEngine.strategyRoll(next).$1 - 1];
      for (final p in next.players) {
        expect(p.cards, hasLength(1));
        expect(p.cards.single.track, track);
      }
      expect(next.drawPiles[track]!.length, 15);
      expect(next.lastCardEvent, contains('3 eligible draw(s)'));
      expect(next.lastCardEvent, isNot(contains('you drew')));
      expect(next.lastCardEvent, isNot(contains('Ben drew')));
      expect(next.lastCardEvent, isNot(contains('Cora drew')));
      checkCards(next);
      checkConservation(next);
    },
  );

  test(
    'empty draw pile reshuffles only spent copies; held copies stay held',
    () {
      var s = prepared();
      final track = StrategyDeck.innovation;
      final players = s.players.toList();
      players[0] = players[0].copyWith(
        developments: {for (final t in StrategyDeck.values) t: 5},
        cards: const [HeldCard(StrategyDeck.innovation, 0)],
      );
      s = s.copyWith(
        players: players,
        phase: MatchPhase.roll,
        drawPiles: {...s.drawPiles, track: []},
        discardPiles: {
          ...s.discardPiles,
          track: List.generate(17, (i) => i + 1),
        },
      );
      // Find a seeded roll whose virtual event die offers Innovation.
      for (var i = 0; i < 100; i++) {
        final candidate = s.copyWith(rollCount: i);
        if (MatchEngine.strategyRoll(candidate.copyWith(rollCount: i + 1)).$1 ==
            1) {
          s = candidate;
          break;
        }
      }
      final next = MatchEngine.roll(s);
      expect(next.current.cards, hasLength(2));
      expect(next.current.cards.last.track, track);
      expect(next.discardPiles[track], isEmpty);
      checkCards(next);
      checkConservation(next);
    },
  );

  test('real card draw, play and imported replay produce identical state', () {
    MatchState? result;
    for (var seed = 1; seed <= 8 && result == null; seed++) {
      var s = MatchEngine.newGame(['A', 'B', 'C'], seed);
      for (var i = 0; i < 6; i++) {
        s = MatchEngine.apply(
          s,
          PlaceVillage(MatchEngine.legalVertices(s).first),
        );
        s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
      }
      for (var turn = 0; turn < 650; turn++) {
        if (s.phase == MatchPhase.invasion) {
          while (s.tactical != null) {
            final w = s.tactical!;
            s = MatchEngine.apply(s, TimeoutTactical(w.id, w.responder));
          }
          s = MatchEngine.apply(s, const ResolveInvasion());
        }
        if (s.phase == MatchPhase.roll) s = MatchEngine.roll(s);
        if (s.phase == MatchPhase.bandit) {
          s = MatchEngine.apply(
            s,
            MoveBandit((s.banditTile + 1) % s.board.tiles.length),
          );
        }
        if (s.phase != MatchPhase.actions) break;
        if (s.active == 0) {
          for (final target in [Resource.wheat, Resource.ore]) {
            if ((s.current.stores[target] ?? 0) >= 5) continue;
            final rate = MatchEngine.tradeRate(s, 0);
            for (final give in [
              Resource.wood,
              Resource.brick,
              Resource.wool,
              Resource.paper,
              Resource.cloth,
              Resource.coin,
            ]) {
              if ((s.current.stores[give] ?? 0) >= rate &&
                  (s.bank[target] ?? 0) > 0) {
                s = MatchEngine.apply(s, BankExchange(give, target));
                break;
              }
            }
          }
          final eligible = s.sites.keys
              .where(
                (v) =>
                    s.sites[v]!.owner == 0 &&
                    s.sites[v]!.structure == Structure.village &&
                    MatchEngine.legalUpgrade(s, v),
              )
              .toList();
          if (eligible.isNotEmpty) {
            s = MatchEngine.apply(s, UpgradeSite(eligible.first));
          }
          if (MatchEngine.canDevelop(s, StrategyDeck.innovation)) {
            s = MatchEngine.apply(
              s,
              const DevelopTown(StrategyDeck.innovation),
            );
          }
        }
        while (s.current.cards.isNotEmpty) {
          final choices = MatchEngine.legalCardPlays(s, 0);
          s = MatchEngine.apply(
            s,
            choices.isEmpty ? const DiscardStrategyCard(0) : choices.first,
          );
          if (s.events.last is PlayStrategyCard) {
            result = s;
            break;
          }
        }
        if (result != null) break;
        s = MatchEngine.apply(s, const EndTurn());
      }
    }
    expect(result, isNotNull);
    final restored = MatchEngine.importReplay(
      MatchEngine.exportReplay(result!),
    );
    expect(MatchEngine.snapshot(restored), MatchEngine.snapshot(result));
    checkConservation(restored);
    checkCards(restored);
  });

  test(
    'seeded event and tier distribution stays within measurable targets',
    () {
      final counts = List<int>.filled(6, 0);
      final qualifying = List<int>.filled(3, 0);
      const samples = 30000;
      for (var seed = 1; seed <= 300; seed++) {
        var s = MatchEngine.newGame(['A', 'B', 'C'], seed);
        for (var index = 1; index <= 100; index++) {
          s = s.copyWith(rollCount: index);
          final (face, tier) = MatchEngine.strategyRoll(s);
          counts[face - 1]++;
          if (face <= 3 && tier <= 3) qualifying[face - 1]++;
        }
      }
      expect(counts.reduce((a, b) => a + b), samples);
      for (var i = 0; i < 3; i++) {
        final share = counts[i] / samples;
        final earned = qualifying[i] / samples;
        expect(
          share,
          inInclusiveRange(.145, .19),
          reason: 'track ${i + 1} event share',
        );
        expect(
          earned,
          inInclusiveRange(.08, .12),
          reason: 'level-three draw opportunity per roll',
        );
      }
    },
  );
}
