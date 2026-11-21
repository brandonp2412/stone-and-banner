import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/ui/match_activity.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('bot celebrates blocking a human road endpoint', (tester) async {
    final base = tableWithSupplies();
    final vertex = base.topology.vertices.firstWhere(
      (v) => v.edges.length >= 2,
    );
    final before = base.copyWith(
      active: 1,
      sites: {},
      roads: {vertex.edges.first: 0},
    );
    final after = before.copyWith(
      sites: {vertex.id: const Site(1, Structure.village)},
      events: [...before.events, PlaceVillage(vertex.id)],
    );
    Widget app(MatchState state) => MaterialApp(
      home: MatchActivity(
        state: state,
        viewerSeat: 0,
        computerSeats: const {1, 2, 3},
      ),
    );
    await tester.pumpWidget(app(before));
    await tester.pumpWidget(app(after));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('${base.players[1].id}: Beat you to it!'), findsOneWidget);
    expect(find.bySemanticsLabel('Cheeky devil emoji'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final roadCount in [1, 2]) {
    testWidgets(
      'village beside $roadCount bot roads reacts to blocked expansion',
      (tester) async {
        final base = tableWithSupplies();
        final vertex = base.topology.vertices.firstWhere(
          (vertex) => vertex.edges.length >= 2,
        );
        final before = base.copyWith(
          active: 0,
          sites: {},
          roads: {for (final edge in vertex.edges.take(roadCount)) edge: 1},
        );
        final after = before.copyWith(
          sites: {vertex.id: const Site(0, Structure.village)},
          events: [...before.events, PlaceVillage(vertex.id)],
        );
        Widget app(MatchState state) => MaterialApp(
          home: Scaffold(
            body: MatchActivity(
              state: state,
              viewerSeat: 0,
              computerSeats: const {1, 2, 3},
            ),
          ),
        );
        await tester.pumpWidget(app(before));
        await tester.pumpWidget(app(after));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('😤'), findsOneWidget);
        {
          expect(
            find.text('${base.players[1].id}: Hey! You cut me off!'),
            findsOneWidget,
          );
          // Other players' later turns do not retrigger this reaction.
          await tester.pump(const Duration(seconds: 3));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('😤'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
