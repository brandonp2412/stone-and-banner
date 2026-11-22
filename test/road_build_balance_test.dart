import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

Offset edgeMidpoint(MatchState state, Size mapSize, int id) {
  final geometry = BoardGeometry(mapSize);
  final edge = state.topology.edges[id];
  return (geometry.vertex(state.topology.vertices[edge.a]) +
          geometry.vertex(state.topology.vertices[edge.b])) /
      2;
}

void main() {
  test('barbarians scale with upgraded sites, not past raids or pressure', () {
    final initial = tableWithSupplies();
    final baseline = initial.copyWith(
      sites: {
        for (final entry in initial.sites.entries)
          entry.key: Site(entry.value.owner, Structure.village),
      },
    );
    expect(MatchEngine.invasionStrength(baseline), 0);
    final villages = baseline.sites.keys.toList();
    final town = baseline.copyWith(
      sites: {
        ...baseline.sites,
        villages[0]: Site(baseline.sites[villages[0]]!.owner, Structure.town),
      },
      invasions: 21,
      reaverPressure: 12,
    );
    expect(MatchEngine.invasionStrength(town), 1);
    final capital = town.copyWith(
      sites: {
        ...town.sites,
        villages[1]: Site(town.sites[villages[1]]!.owner, Structure.capital),
      },
      invasions: 101,
      reaverPressure: 25,
    );
    expect(MatchEngine.invasionStrength(capital), 2);
    expect(
      MatchEngine.invasionStrength(
        capital.copyWith(invasions: 0, reaverPressure: 0),
      ),
      2,
    );
  });

  testWidgets('tap owned road to choose extension and build directly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var state = tableWithSupplies();
    final originalRoads = state.roads.length;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => MatchView(
              state: state,
              onEvent: (event) =>
                  refresh(() => state = MatchEngine.apply(state, event)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mapFinder = find.byKey(const ValueKey('realm-map'));
    Offset position(int id) =>
        tester.getTopLeft(mapFinder) +
        edgeMidpoint(state, tester.getSize(mapFinder), id);
    final existing = state.roads.keys.firstWhere(
      (id) => state.roads[id] == state.active,
    );
    await tester.tapAt(position(existing));
    await tester.pumpAndSettle();
    expect(find.text('Extend your road?'), findsOneWidget);
    expect(find.textContaining('Cost:'), findsWidgets);

    await tester.tap(find.text('Choose location'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cancel selection'), findsOneWidget);
    expect(find.text('Build a road'), findsNothing);
    final nextEdge = MatchEngine.legalEdges(state).first;
    await tester.tapAt(position(nextEdge));
    await tester.pumpAndSettle();
    expect(find.text('Build this road?'), findsNothing);
    expect(state.roads[nextEdge], state.active);
    expect(state.roads.length, originalRoads + 1);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('upgrade button exposes actual town and capital costs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build').hitTestable());
    await tester.pumpAndSettle();
    expect(find.textContaining('Town: 2 wheat · 3 ore'), findsWidgets);
    expect(find.textContaining('Capital: 2 wheat · 2 ore'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
