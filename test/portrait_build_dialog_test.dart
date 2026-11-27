import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'portrait_visual_audit_test.dart' show portraitSetup, renderMatch;
import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('portrait junction choices fit and dispatch the correct event', (
    tester,
  ) async {
    await portraitSetup(tester);
    final original = tableWithSupplies();
    final junction = Iterable<int>.generate(original.topology.vertices.length)
        .firstWhere(
          (v) =>
              !original.sites.containsKey(v) &&
              !original.guards.containsKey(v) &&
              !original.topology
                  .neighbours(v)
                  .any(original.sites.containsKey) &&
              original.topology.vertices[v].edges.any(
                (e) => !original.roads.containsKey(e),
              ),
        );
    final edge = original.topology.vertices[junction].edges.firstWhere(
      (e) => !original.roads.containsKey(e),
    );
    final state = original.copyWith(
      roads: {...original.roads, edge: original.active},
    );
    MatchEvent? event;
    await renderMatch(tester, state: state);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'NotoSans',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffe7bf7b),
            brightness: Brightness.dark,
            surface: const Color(0xff192529),
          ),
        ),
        home: MatchView(state: state, onEvent: (value) => event = value),
      ),
    );
    await tester.pumpAndSettle();
    final board = find.byKey(const ValueKey('realm-map'));
    await tester.tapAt(
      tester.getTopLeft(board) +
          BoardGeometry(tester.getSize(board))
              .vertex(state.topology.vertices[junction]),
    );
    await tester.pumpAndSettle();
    final village = find.byKey(const ValueKey('build-village-at-junction'));
    final guard = find.byKey(const ValueKey('build-guard-at-junction'));
    expect(village, findsOneWidget);
    expect(guard, findsOneWidget);
    expect(tester.getSize(village).width, tester.getSize(guard).width);
    expect(tester.getRect(village).bottom, lessThan(tester.getRect(guard).top));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/portrait_junction_choices.png'),
    );
    await tester.tap(guard);
    await tester.pumpAndSettle();
    expect(event, isA<RecruitGuard>());
  });

  for (final size in [
    const Size(320, 640),
    const Size(393, 852),
    const Size(640, 320),
  ]) {
    testWidgets('city fall animation stays within viewport at $size', (
      tester,
    ) async {
      await portraitSetup(tester);
      tester.view.physicalSize = size;
      final before = tableWithSupplies().copyWith(
        sites: {0: const Site(0, Structure.capital)},
      );
      final after = before.copyWith(
        sites: {0: const Site(0, Structure.town)},
        invasions: before.invasions + 1,
      );
      await renderMatch(tester, state: before);
      Widget app(MatchState state) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'NotoSans',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffe7bf7b),
            brightness: Brightness.dark,
            surface: const Color(0xff192529),
          ),
        ),
        home: Scaffold(
          body: MatchView(state: state, visibleSeat: 0, onEvent: (_) {}),
        ),
      );
      await tester.pumpWidget(app(before));
      await tester.pump();
      await tester.pumpWidget(app(after));
      final panel = find.byKey(const ValueKey('city-fall-panel'));
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 70));
        final rect = tester.getRect(panel);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
        if (frame == 7 && size.width == 393) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/portrait_city_fall.png'),
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
