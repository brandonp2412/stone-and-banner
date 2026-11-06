import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

MatchState _prepared() {
  var s = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 321);
  for (var i = 0; i < 6; i++) {
    s = MatchEngine.apply(s, PlaceVillage(MatchEngine.legalVertices(s).first));
    s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
  }
  final bank = Map<Resource, int>.of(s.bank);
  final players = s.players.toList();
  for (var player = 0; player < 2; player++) {
    final stores = Map<Resource, int>.of(players[player].stores);
    for (final good in Resource.values) {
      final amount = player == 0 ? 5 : 2;
      bank[good] = bank[good]! - amount;
      stores[good] = (stores[good] ?? 0) + amount;
    }
    players[player] = players[player].copyWith(stores: stores);
  }
  final own = s.sites.keys.firstWhere((v) => s.sites[v]!.owner == 0);
  final second = s.sites.keys.firstWhere(
    (v) => s.sites[v]!.owner == 0 && v != own,
  );
  final rival = s.sites.keys.firstWhere((v) => s.sites[v]!.owner == 1);
  return s.copyWith(
    phase: MatchPhase.actions,
    players: players,
    bank: bank,
    sites: {...s.sites, own: const Site(0, Structure.town)},
    knights: {
      own: const KnightPiece(0, KnightRank.sentinel, false, -1),
      second: const KnightPiece(0, KnightRank.warden, true, -1),
      rival: const KnightPiece(1, KnightRank.sentinel, true, -1),
    },
  );
}

MatchState _holdCopy(
  MatchState s,
  StrategyDeck track,
  int index, {
  int seat = 0,
}) {
  final pile = s.drawPiles[track]!.toList();
  expect(pile.remove(index), isTrue);
  final players = s.players.toList();
  players[seat] = players[seat].copyWith(
    cards: [...players[seat].cards, HeldCard(track, index)],
  );
  return s.copyWith(players: players, drawPiles: {...s.drawPiles, track: pile});
}

MatchState _holdId(MatchState s, String id, {int seat = 0}) {
  final track = StrategyCards.definitions.firstWhere((d) => d.id == id).track;
  final index = s.drawPiles[track]!.firstWhere(
    (i) => StrategyCards.deck(track)[i].id == id,
  );
  return _holdCopy(s, track, index, seat: seat);
}

void _conserved(MatchState s) {
  for (final good in Resource.values) {
    final held = s.players.fold<int>(
      0,
      (sum, p) => sum + (p.stores[good] ?? 0),
    );
    final escrow = s.offers
        .where((o) => o.give == good)
        .fold<int>(0, (sum, o) => sum + o.giveCount);
    expect(
      s.bank[good]! + held + escrow,
      MatchEngine.bankSupply,
      reason: good.name,
    );
    expect(s.bank[good], greaterThanOrEqualTo(0));
    for (final p in s.players) {
      expect(p.stores[good] ?? 0, greaterThanOrEqualTo(0));
    }
  }
  for (final track in StrategyDeck.values) {
    final physical = <int>[
      ...s.drawPiles[track]!,
      ...s.discardPiles[track]!,
      for (final p in s.players)
        for (final c in p.cards)
          if (c.track == track) c.index,
    ]..sort();
    expect(
      physical,
      List.generate(18, (i) => i),
      reason: '${track.name}: every card index occurs exactly once',
    );
  }
}

void main() {
  test(
    'every one of 54 physical copies exposes distinct reducer-accepted targets',
    () {
      final base = _prepared();
      var copies = 0;
      var choices = 0;
      for (final track in StrategyDeck.values) {
        expect(StrategyCards.deck(track), hasLength(18));
        for (var index = 0; index < 18; index++) {
          final s = _holdCopy(base, track, index);
          final definition = StrategyCards.deck(track)[index];
          final legal = MatchEngine.legalCardPlays(s, 0);
          expect(
            legal,
            isNotEmpty,
            reason: '${track.name} #$index ${definition.name}',
          );
          expect(
            legal.map((e) => jsonEncode(e.toJson())).toSet().length,
            legal.length,
            reason:
                '${definition.name} must not repeat target/exchange choices',
          );
          for (final option in legal) {
            final next = MatchEngine.apply(s, option);
            expect(
              next.events.last.toJson(),
              option.toJson(),
              reason: '${definition.name} option ${option.toJson()}',
            );
            expect(
              next.current.cards,
              isEmpty,
              reason: '${definition.name} must consume once',
            );
            expect(next.discardPiles[track], hasLength(1));
            _conserved(next);
            expect(
              () => MatchEngine.apply(next, option),
              throwsStateError,
              reason: 'duplicate ${definition.name} must fail',
            );
            choices++;
          }
          copies++;
        }
      }
      expect(copies, 54);
      expect(choices, greaterThan(54));
      // Report the actual enumerated reducer choices for the evidence ledger.
      // ignore: avoid_print
      print(
        'SLICE15_CARD_MATRIX: $copies physical copies, $choices legal options',
      );
    },
  );

  test(
    'empty stock makes bank-dependent cards unplayable without deadlocking',
    () {
      var s = _prepared();
      final bank = Map<Resource, int>.of(s.bank);
      final players = s.players.toList();
      final stores = Map<Resource, int>.of(players[2].stores);
      for (final good in Resource.values) {
        stores[good] = (stores[good] ?? 0) + bank[good]!;
        bank[good] = 0;
      }
      players[2] = players[2].copyWith(stores: stores);
      s = s.copyWith(bank: bank, players: players);
      for (final definition in StrategyCards.definitions.where(
        (d) => {
          CardPower.fixedGoods,
          CardPower.chooseBasic,
          CardPower.chooseCommodity,
          CardPower.swap,
          CardPower.portSwap,
          CardPower.leverageSwap,
        }.contains(d.power),
      )) {
        final held = _holdId(s, definition.id);
        expect(
          MatchEngine.legalCardPlays(held, 0),
          isEmpty,
          reason: definition.name,
        );
        expect(MatchEngine.apply(held, const EndTurn()).phase, MatchPhase.roll);
        final discarded = MatchEngine.apply(held, const DiscardStrategyCard(0));
        expect(discarded.current.cards, isEmpty);
        _conserved(discarded);
      }
    },
  );

  test('pending standing offer prevents playing a Strategy Card', () {
    var s = _holdId(_prepared(), 'forecast');
    s = MatchEngine.apply(
      s,
      const ProposeTrade(1, Resource.wood, 1, Resource.brick, 1),
    );
    expect(s.offers, hasLength(1));
    expect(MatchEngine.legalCardPlays(s, 0), isEmpty);
    expect(
      () => MatchEngine.apply(
        s,
        const PlayStrategyCard(0, receive: Resource.wood),
      ),
      throwsStateError,
    );
    final discarded = MatchEngine.apply(s, const DiscardStrategyCard(0));
    _conserved(discarded);
  });

  test(
    'three targeted Governance attacks: counter, pass and timeout settle once',
    () {
      for (final attackId in [
        'political-pressure',
        'supply-raid',
        'defection',
      ]) {
        final counterId = attackId == 'defection'
            ? 'defection'
            : 'boundary-dispute';
        var s = _holdId(_prepared(), attackId);
        s = _holdId(s, counterId, seat: 1);
        final attack = MatchEngine.legalCardPlays(s, 0).firstWhere(
          (e) => attackId == 'defection'
              ? s.knights[e.vertex]?.owner == 1
              : e.target == 1 && e.receive == Resource.ore,
        );
        final open = MatchEngine.apply(s, attack);
        expect(open.tactical?.kind, TacticalKind.governance, reason: attackId);
        final w = open.tactical!;
        expect(w.responder, 1);
        expect(
          () => MatchEngine.apply(
            open,
            RespondTactical(w.id + 1, 1, TacticalChoice.pass),
          ),
          throwsStateError,
        );
        final blocked = MatchEngine.apply(
          open,
          RespondTactical(w.id, 1, TacticalChoice.counter, cardIndex: 0),
        );
        expect(blocked.tactical, isNull);
        expect(blocked.players[0].cards, isEmpty);
        expect(blocked.players[1].cards, isEmpty);
        expect(blocked.discardPiles[StrategyDeck.governance], hasLength(2));
        expect(
          blocked.players[1].stores,
          s.players[1].stores,
          reason: attackId,
        );
        _conserved(blocked);
        expect(
          () => MatchEngine.apply(
            blocked,
            RespondTactical(w.id, 1, TacticalChoice.counter, cardIndex: 0),
          ),
          throwsStateError,
        );
        final passed = MatchEngine.apply(
          open,
          RespondTactical(w.id, 1, TacticalChoice.pass),
        );
        final timed = MatchEngine.apply(open, TimeoutTactical(w.id, 1));
        expect(passed.tactical, isNull);
        expect(timed.tactical, isNull);
        expect(
          passed.players.map((p) => p.stores).toList(),
          timed.players.map((p) => p.stores).toList(),
        );
        expect(passed.knights.keys.toSet(), timed.knights.keys.toSet());
        for (final vertex in passed.knights.keys) {
          final a = passed.knights[vertex]!;
          final b = timed.knights[vertex]!;
          expect(
            (a.owner, a.rank, a.active, a.actedTurn),
            (b.owner, b.rank, b.active, b.actedTurn),
          );
        }
        expect(passed.discardPiles, timed.discardPiles);
        expect(passed.players[0].cards, isEmpty);
        expect(passed.players[1].cards, hasLength(1));
        _conserved(passed);
        _conserved(timed);
      }
    },
  );
}
