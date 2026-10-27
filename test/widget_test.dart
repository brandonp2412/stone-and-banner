import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/engine/match.dart';

Future<void> ready(WidgetTester tester) async {
  await tester.tap(find.text("I'm ready"));
  await tester.pumpAndSettle();
}

Future<void> tapVertex(WidgetTester tester, MatchState state, int id) async {
  final found = find.byType(InteractiveViewer);
  final size = tester.getSize(found);
  final origin = tester.getTopLeft(found);
  final radius = math.min(size.width / 9.8, size.height / 9.3);
  final v = state.topology.vertices[id];
  await tester.tapAt(
    origin +
        Offset(size.width / 2 + v.x * radius, size.height / 2 + v.y * radius),
  );
  await tester.pumpAndSettle();
}

Future<void> tapEdge(WidgetTester tester, MatchState state, int id) async {
  final found = find.byType(InteractiveViewer);
  final size = tester.getSize(found);
  final origin = tester.getTopLeft(found);
  final radius = math.min(size.width / 9.8, size.height / 9.3);
  final e = state.topology.edges[id];
  final a = state.topology.vertices[e.a], b = state.topology.vertices[e.b];
  await tester.tapAt(
    origin +
        Offset(
          size.width / 2 + (a.x + b.x) / 2 * radius,
          size.height / 2 + (a.y + b.y) / 2 * radius,
        ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('full 3-seat placement draft, privacy handoff and seeded roll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const StoneBannerApp());
    expect(find.text('Raise a town. Shape a realm.'), findsOneWidget);
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
      expect(find.textContaining('glowing side'), findsOneWidget);
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
    expect(find.text('Roll dice'), findsOneWidget);
    await tester.ensureVisible(find.text('Roll dice'));
    await tester.tap(find.text('Roll dice'));
    await tester.pumpAndSettle();
    expect(find.text('Roll dice'), findsNothing);
  });

  testWidgets('landscape board stays readable in bounded width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const StoneBannerApp());
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    await ready(tester);
    expect(tester.getSize(find.byType(InteractiveViewer)).width, lessThan(680));
  });

  testWidgets('rules accessible from navigation', (tester) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
    expect(find.text('The founding rules'), findsOneWidget);
    expect(find.text('Claim'), findsOneWidget);
  });
}
