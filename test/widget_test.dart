import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/engine/match.dart';

Future<void> ready(WidgetTester tester) async {
  await tester.tap(find.text("I'm ready"));
  await tester.pumpAndSettle();
}

Future<void> tapVertex(WidgetTester tester, MatchState state, int id) async {
  final found = find.byKey(const ValueKey('realm-map'));
  final size = tester.getSize(found);
  final origin = tester.getTopLeft(found);
  await tester.tapAt(
    origin + BoardGeometry(size).vertex(state.topology.vertices[id]),
  );
  await tester.pumpAndSettle();
}

Future<void> tapEdge(WidgetTester tester, MatchState state, int id) async {
  final found = find.byKey(const ValueKey('realm-map'));
  final size = tester.getSize(found);
  final origin = tester.getTopLeft(found);
  final g = BoardGeometry(size);
  final e = state.topology.edges[id];
  await tester.tapAt(
    origin +
        (g.vertex(state.topology.vertices[e.a]) +
                g.vertex(state.topology.vertices[e.b])) /
            2,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('full 3-seat placement draft, privacy handoff and seeded roll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const StoneBannerApp());
    expect(find.text('Raise a town.\nShape a realm.'), findsOneWidget);
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);
    var state = MatchEngine.newGame([
      'Player 1',
      'Player 2',
      'Player 3',
    ], 20261027);
    for (var n = 0; n < 6; n++) {
      if (find.text('Pass the device').evaluate().isNotEmpty) {
        await ready(tester);
      }
      final v = MatchEngine.legalVertices(state).first;
      await tapVertex(tester, state, v);
      state = MatchEngine.apply(state, PlaceVillage(v));
      expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
      final edge = MatchEngine.legalEdges(state).first;
      await tapEdge(tester, state, edge);
      state = MatchEngine.apply(state, PlaceRoad(edge));
      if (n != 2 && n != 5) {
        expect(find.text('Pass the device'), findsOneWidget);
      }
    }
    if (find.text('Pass the device').evaluate().isNotEmpty) {
      await ready(tester);
    }
    expect(find.text('Roll'), findsOneWidget);
    await tester.ensureVisible(find.text('Roll'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roll'));
    await tester.pumpAndSettle();
    expect(find.text('Roll'), findsNothing);
  });

  testWidgets('landscape board stays readable in bounded width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const StoneBannerApp());
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    await ready(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('realm-map'))).width,
      greaterThan(1200),
    );
  });

  testWidgets('rules accessible from navigation', (tester) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.ensureVisible(find.text('Learn the rules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn the rules'));
    await tester.pumpAndSettle();
    expect(find.text('The founding rules'), findsOneWidget);
    await tester.tap(find.text('Setup and turn order'));
    await tester.pumpAndSettle();
    expect(find.text('Your first two placements'), findsOneWidget);

    final search = find.byType(TextField);
    await tester.enterText(search, 'REAVER looting');
    await tester.pumpAndSettle();
    expect(find.text('Governance (Ore Hills and coin)'), findsOneWidget);
    expect(find.text('Your first two placements'), findsNothing);

    await tester.enterText(search, 'ore aid');
    await tester.pumpAndSettle();
    expect(find.text('Pledging emergency aid'), findsOneWidget);
    expect(find.text('When the fleet attacks'), findsNothing);

    await tester.enterText(search, 'Royal Audit');
    await tester.pumpAndSettle();
    expect(find.text('The Royal Audit'), findsOneWidget);

    await tester.enterText(search, 'unmatched query');
    await tester.pumpAndSettle();
    expect(find.text('No rules match your search.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Setup and turn order'), findsOneWidget);
  });
}
