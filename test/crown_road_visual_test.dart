import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_activity.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

List<int> pathOfLength(BoardTopology topology, int length) {
  List<int>? walk(int vertex, List<int> path, Set<int> visited) {
    if (path.length == length) return path;
    for (final id in topology.vertices[vertex].edges) {
      final edge = topology.edges[id];
      final to = edge.a == vertex ? edge.b : edge.a;
      if (visited.contains(to)) continue;
      final found = walk(to, [...path, id], {...visited, to});
      if (found != null) return found;
    }
    return null;
  }

  for (final v in topology.vertices) {
    final found = walk(v.id, [], {v.id});
    if (found != null) return found;
  }
  throw StateError('Could not make a route');
}

MatchState longRoad() {
  final game = MatchEngine.newGame(['A', 'B', 'C', 'D'], 818);
  final route = pathOfLength(game.topology, 5);
  return game.copyWith(
    phase: MatchPhase.actions,
    roads: {for (final edge in route) edge: 0},
  );
}

void main() {
  test('highlighted road is an actual connected scoring route', () {
    final game = longRoad();
    final path = MatchEngine.crownRoadPath(game, 0);
    expect(path.length, MatchEngine.crownRoad(game, 0));
    expect(path.toSet().length, path.length);
    for (var i = 0; i < path.length - 1; i++) {
      final a = game.topology.edges[path[i]];
      final b = game.topology.edges[path[i + 1]];
      expect({a.a, a.b}.intersection({b.a, b.b}), isNotEmpty);
    }
  });

  testWidgets('crown road ownership change animates and clears', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initial = longRoad();
    Widget app(MatchState state) => MaterialApp(
      home: MatchView(state: state, onEvent: (_) {}),
    );
    await tester.pumpWidget(app(initial));
    await tester.pump();
    await tester.pumpWidget(app(initial.copyWith(crownRoadHolder: 0)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey('crown-road-award-animation')),
      findsOneWidget,
    );
    expect(find.text('🏆 CROWN ROAD!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('crown-road-award-animation')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final reducedMotion in [false, true]) {
    testWidgets('guard breaks Crown Road; reduced motion $reducedMotion', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
      final base = longRoad();
      final route = MatchEngine.crownRoadPath(base, 0);
      final a = base.topology.edges[route[1]];
      final b = base.topology.edges[route[2]];
      final blocker = {a.a, a.b}.intersection({b.a, b.b}).single;
      final before = base.copyWith(crownRoadHolder: 0);
      final after = before.copyWith(
        clearRoadHolder: true,
        guards: {blocker: const GuardPiece(1, GuardRank.sentinel, true, 0)},
        events: [...before.events, MoveGuard(0, blocker)],
      );
      expect(MatchEngine.crownRoad(after, 0), 3);
      Widget app(MatchState state) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: MatchView(state: state, onEvent: (_) {}),
        ),
      );
      await tester.pumpWidget(app(before));
      await tester.pump();
      await tester.pumpWidget(app(after));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('crown-road-break-animation')),
        reducedMotion ? findsNothing : findsOneWidget,
      );
      if (!reducedMotion) {
        expect(find.text('💔 CROWN ROAD BROKEN'), findsOneWidget);
        expect(find.text('A: 5 → 3 roads · −2 Renown'), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('crown-road-break-animation')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('bot offer does not generate duplicate activity toast', (
    tester,
  ) async {
    final before = MatchEngine.newGame([
      'Human',
      'Bot',
      'Other',
    ], 819).copyWith(active: 1, phase: MatchPhase.actions);
    final after = before.copyWith(
      events: [
        ...before.events,
        const ProposeTrade(0, Resource.wood, 1, Resource.brick, 1),
      ],
    );
    Widget app(MatchState state) => MaterialApp(
      home: MatchActivity(
        state: state,
        viewerSeat: 0,
        computerSeats: const {1},
      ),
    );
    await tester.pumpWidget(app(before));
    await tester.pumpWidget(app(after));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('match-activity-notice')), findsNothing);
  });
}
