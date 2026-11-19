import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

MatchState townState(int seed, {bool town = true}) {
  final state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], seed);
  return state.copyWith(
    phase: MatchPhase.actions,
    sites: {0: Site(0, town ? Structure.town : Structure.village)},
  );
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_seen_v1': ['actions'],
    }),
  );

  Future<void> showMatch(WidgetTester tester, MatchState state) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(state: state, onEvent: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('town hint leaves the board paintable with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await showMatch(tester, townState(11));
    expect(find.byKey(const ValueKey('town-production-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final boardRect = tester.getRect(find.byKey(const ValueKey('realm-map')));
    await tester.tap(find.byTooltip('Dismiss hint'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('realm-map'))), boardRect);
  });

  testWidgets('first town hint opens Realm and stays dismissed across games', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showMatch(tester, townState(10, town: false));
    final hint = find.byKey(const ValueKey('town-production-hint'));
    expect(hint, findsNothing);
    await showMatch(tester, townState(10));
    expect(hint, findsOneWidget);
    expect(find.textContaining('Develop your Town in Realm'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.descendant(of: hint, matching: find.text('Realm')));
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    await tester.scrollUntilVisible(
      find.text('Town Developments'),
      150,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('mobile-action-hub')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Town Developments'), findsOneWidget);
    await showMatch(tester, townState(10).copyWith(round: 2));
    expect(hint, findsNothing);
    await showMatch(tester, townState(11));
    expect(hint, findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('gameplay_hints_seen_v1'), contains('town'));
  });

  testWidgets('hint setting persists and suppresses hints in a new match', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showMatch(tester, townState(20));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('town-production-hint')),
        matching: find.text('Realm'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Gameplay hints'),
      300,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('panel-3')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gameplay hints'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('gameplay_hints_enabled'), false);
    await tester.pumpWidget(const SizedBox());
    await showMatch(tester, townState(21));
    expect(find.byKey(const ValueKey('town-production-hint')), findsNothing);
    await tester.tap(find.text('Realm'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Gameplay hints'),
      300,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('panel-3')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      false,
    );
    await tester.scrollUntilVisible(
      find.text('Gameplay hints'),
      300,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('panel-3')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gameplay hints'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('gameplay_hints_enabled'), true);
    expect(find.byKey(const ValueKey('town-production-hint')), findsNothing);
    expect(find.byKey(const ValueKey('gameplay-hint-realm')), findsOneWidget);
  });
}
