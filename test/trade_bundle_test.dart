import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/ai_cards.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'action_helpers.dart';
import 'landscape_tabletop_test.dart' show tableWithSupplies;

MatchState stocked() {
  final s = MatchEngine.newGame([
    'A',
    'B',
    'C',
  ], 71).copyWith(phase: MatchPhase.actions);
  final players = s.players.toList();
  players[0] = players[0].copyWith(
    stores: {Resource.ore: 4, Resource.wheat: 4},
  );
  players[1] = players[1].copyWith(
    stores: {Resource.wood: 3, Resource.wool: 3},
  );
  return s.copyWith(players: players);
}

const bundle = ProposeTrade(
  1,
  Resource.ore,
  2,
  Resource.wood,
  1,
  giveBundle: {Resource.ore: 2, Resource.wheat: 2},
  wantBundle: {Resource.wood: 1, Resource.wool: 1},
);

void main() {
  testWidgets('composer adds another resource to an offer', (tester) async {
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(state: tableWithSupplies(), onEvent: events.add),
        ),
      ),
    );
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Player trade');
    await tester.tap(find.text('Player trade'));
    await tester.pumpAndSettle();
    final addWheat = find.byKey(const ValueKey('trade-give-wheat'));
    await tester.ensureVisible(addWheat);
    await tester.tap(addWheat);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send offer'));
    await tester.pumpAndSettle();
    final offer = events.whereType<ProposeTrade>().single;
    expect(offer.gives.length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('bundle events survive replay export and import', () {
    var s = MatchEngine.newGame(['A', 'B', 'C'], 71);
    while (s.phase != MatchPhase.actions) {
      final view = AiActionAdapter.observe(s, s.active);
      s = MatchEngine.apply(s, view.legalActions.first);
    }
    final goods = Resource.values
        .where((g) => (s.current.stores[g] ?? 0) > 0)
        .take(2)
        .toList();
    expect(goods.length, 2);
    final want = Resource.values.firstWhere((g) => !goods.contains(g));
    s = MatchEngine.apply(
      s,
      ProposeTrade(
        (s.active + 1) % 3,
        goods.first,
        1,
        want,
        1,
        giveBundle: {for (final g in goods) g: 1},
      ),
    );
    final restored = MatchEngine.importReplay(MatchEngine.exportReplay(s));
    expect(MatchEngine.snapshot(restored), MatchEngine.snapshot(s));
  });

  test(
    'mixed bundles transfer every resource and round trip over the wire',
    () {
      final decoded = RoomProtocol.eventFromJson(bundle.toJson());
      var s = MatchEngine.apply(stocked(), decoded);
      final view = RoomProtocol.readView(RoomProtocol.view(s, 1));
      expect(view.offers.single.gives, bundle.gives);
      expect(view.offers.single.wants, bundle.wants);
      expect(s.players[0].stores[Resource.ore], 4);
      s = MatchEngine.apply(
        s,
        RespondTrade(1, true, offerId: s.offers.single.id),
      );
      expect(s.players[0].stores, {
        Resource.ore: 2,
        Resource.wheat: 2,
        Resource.wood: 1,
        Resource.wool: 1,
      });
      expect(s.players[1].stores, {
        Resource.wood: 2,
        Resource.wool: 2,
        Resource.ore: 2,
        Resource.wheat: 2,
      });
    },
  );

  test('acceptance checks every offered and requested resource atomically', () {
    final offered = MatchEngine.apply(stocked(), bundle);
    for (final seat in [0, 1]) {
      final players = offered.players.toList();
      final stores = Map<Resource, int>.of(players[seat].stores);
      stores.remove(seat == 0 ? Resource.wheat : Resource.wool);
      players[seat] = players[seat].copyWith(stores: stores);
      final s = offered.copyWith(players: players);
      expect(
        () => MatchEngine.apply(
          s,
          RespondTrade(1, true, offerId: s.offers.single.id),
        ),
        throwsStateError,
      );
      expect(s.players[seat].stores, stores);
    }
  });

  test('invalid bundle counts and overlapping resources are rejected', () {
    for (final gives in [
      <Resource, int>{},
      {Resource.ore: 0},
      {Resource.ore: -1},
      {Resource.ore: 5},
      {Resource.wood: 1},
    ]) {
      expect(
        () => MatchEngine.apply(
          stocked(),
          ProposeTrade(1, Resource.ore, 1, Resource.wood, 1, giveBundle: gives),
        ),
        throwsStateError,
      );
    }
  });

  test('AI retains bundles but prefers a recipient-friendly trade', () {
    final base = stocked();
    // Stock is private; candidates may only ask for goods an opponent's
    // visible villages could actually produce.
    final sites = <int, Site>{};
    for (final good in [Resource.wood, Resource.wool]) {
      final vertex = base.topology.vertices.firstWhere(
        (vertex) =>
            !sites.containsKey(vertex.id) &&
            vertex.tiles.any(
              (tile) => base.board.tiles[tile].land.produces == good,
            ),
      );
      sites[vertex.id] = const Site(1, Structure.village);
    }
    var s = base.copyWith(sites: sites);
    // An offer is only attempted on a deterministic subset of turns.
    for (var round = 1; round <= 100; round++) {
      s = s.copyWith(round: round);
      if (AiActionAdapter.observe(s, 0).triesPlayerTrade) break;
    }
    final view = AiActionAdapter.observe(s, 0);
    expect(view.triesPlayerTrade, isTrue);
    final offers = view.legalActions.whereType<ProposeTrade>();
    expect(offers.any((o) => o.gives.length > 1 && o.wants.length > 1), isTrue);
    expect(offers.any((o) => o.gives.values.any((n) => n > 1)), isTrue);
    final chosen = AiCardStrategy.propose(view) as ProposeTrade;
    // A balanced two-resource offer is fine; demanding multiple copies of
    // one scarce resource is what the AI must avoid.
    expect(chosen.wants.values.every((count) => count == 1), isTrue);
    expect(canPayTrade(s.current.stores, chosen.gives), isTrue);
    MatchEngine.apply(s, chosen);
  });
}
