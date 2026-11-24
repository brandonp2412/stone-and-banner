import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'advanced_test.dart' show draft, fund;

import 'landscape_tabletop_test.dart' show display, tableWithSupplies;

void main() {
  testWidgets('bandit victim selection can be cancelled without moving', (
    tester,
  ) async {
    var state = draft(55).copyWith(active: 1, phase: MatchPhase.actions);
    state = fund(state, 1, MatchEngine.effectiveRoadCost(state));
    state = MatchEngine.apply(
      state,
      PlaceRoad(MatchEngine.legalEdges(state).first),
    );
    state = state.copyWith(active: 0, phase: MatchPhase.bandit);
    final tile = List.generate(state.board.tiles.length, (i) => i).firstWhere(
      (i) =>
          i != state.banditTile &&
          MatchEngine.banditVictims(state, i).contains(1),
    );
    final events = <MatchEvent>[];
    await display(tester, const Size(844, 390), state, onEvent: events.add);
    final map = find.byKey(const ValueKey('realm-map'));
    final point =
        tester.getTopLeft(map) +
        BoardGeometry(tester.getSize(map))
            .tile(state.board.tiles[tile].position);
    for (final cancelByTap in [false, true]) {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.text('Bandit · choose who to rob'), findsOneWidget);
      if (cancelByTap) {
        await tester.tapAt(const Offset(1, 1));
      } else {
        await tester.tap(find.text('Cancel'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Bandit · choose who to rob'), findsNothing);
      expect(events, isEmpty);
    }
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, state.players[1].id));
    await tester.pumpAndSettle();
    expect(events.single, isA<MoveBandit>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('affordable village without a legal site is disabled', (
    tester,
  ) async {
    final state = tableWithSupplies().copyWith(roads: <int, int>{});
    expect(MatchEngine.legalVertices(state), isEmpty);
    await display(tester, const Size(844, 390), state);
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Extend a road first'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Village'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'player trade displays quantity controls without escrow language',
    (tester) async {
      await display(tester, const Size(844, 390), tableWithSupplies());
      await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trade'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('Player trade'));
      await tester.pumpAndSettle();
      final giveWood = find.byKey(const ValueKey('trade-give-wood'));
      final getWheat = find.byKey(const ValueKey('trade-get-wheat'));
      expect(tester.widget<InkWell>(giveWood).onTap, isNotNull);
      expect(tester.widget<InkWell>(getWheat).onTap, isNotNull);
      await tester.tap(giveWood);
      await tester.tap(getWheat);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove one wood from offer'), findsOneWidget);
      expect(find.byTooltip('Remove one wheat from request'), findsOneWidget);
      expect(find.textContaining('escrow', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('board target picker is absent', (tester) async {
    final state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 20261118);
    await display(tester, const Size(844, 390), state);
    expect(find.byTooltip('Choose target'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
