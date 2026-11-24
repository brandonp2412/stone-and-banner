import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/ui/focus_hint.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'board_target_helpers.dart';
import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> showMatch(
    WidgetTester tester,
    MatchState state, {
    bool observing = false,
    int? seat,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: state,
            onEvent: (_) {},
            observing: observing,
            visibleSeat: seat,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Dismiss hint'));
    await tester.pumpAndSettle();
  }

  for (final entry in {
    MatchPhase.setupVillage: 'setupVillage',
    MatchPhase.setupRoad: 'setupRoad',
    MatchPhase.roll: 'roll',
    MatchPhase.bandit: 'bandit',
    MatchPhase.invasion: 'invasion',
  }.entries) {
    testWidgets(
      '${entry.key.name} explains first occurrence and remembers it',
      (tester) async {
        final initial = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 13);
        final state = initial.copyWith(phase: entry.key);
        await showMatch(tester, state);
        expect(
          find.byKey(ValueKey('gameplay-hint-${entry.value}')),
          findsOneWidget,
        );
        await dismiss(tester);
        expect(find.byType(FocusHint), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getStringList('gameplay_hints_seen_v1'),
          contains(entry.value),
        );
        await tester.pumpWidget(const SizedBox());
        await showMatch(
          tester,
          MatchEngine.newGame([
            'Ada',
            'Ben',
            'Cora',
          ], 14).copyWith(phase: entry.key),
        );
        expect(find.byType(FocusHint), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('roll hint highlights the actual dice button on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showMatch(
      tester,
      MatchEngine.newGame([
        'Ada',
        'Ben',
        'Cora',
      ], 13).copyWith(phase: MatchPhase.roll),
    );
    final hint = tester.widget<FocusHint>(find.byType(FocusHint));
    final button = find.widgetWithText(FilledButton, 'Roll');
    expect(button, findsOneWidget);
    expect(hint.target.currentContext, isNotNull);
    expect(tester.getRect(find.byKey(hint.target)), tester.getRect(button));
    expect(tester.takeException(), isNull);
  });

  testWidgets('board does not expose a coordinate-free accessibility tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 13);
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(state: state, onEvent: events.add),
      ),
    );
    await tester.pumpAndSettle();
    final map = find.byKey(const ValueKey('realm-map'));
    expect(tester.getSemantics(map).label, contains('Realm map'));
    expect(
      tester
          .getSemantics(map)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    await tapBoardTarget(
      tester,
      state,
      vertex: MatchEngine.legalVertices(state).first,
    );
    expect(events.single, isA<PlaceVillage>());
    semantics.dispose();
  });

  testWidgets('second setup village explains the free Town', (tester) async {
    final initial = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 13);
    await showMatch(
      tester,
      initial.copyWith(setupStep: initial.players.length),
    );
    expect(
      find.byKey(const ValueKey('gameplay-hint-setupTown')),
      findsOneWidget,
    );
  });

  testWidgets(
    'tabs and building actions explain themselves without cascading',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'gameplay_hints_seen_v1': ['town'],
      });
      final state = tableWithSupplies();
      await showMatch(tester, state);
      expect(
        find.byKey(const ValueKey('gameplay-hint-actions')),
        findsOneWidget,
      );
      await dismiss(tester);
      expect(find.byType(FocusHint), findsNothing);
      for (final tab in ['Trade', 'Cards', 'Realm']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('gameplay-hint-${tab.toLowerCase()}')),
          findsOneWidget,
        );
        await dismiss(tester);
        expect(find.byType(FocusHint), findsNothing);
      }
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Road'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gameplay-hint-road')), findsOneWidget);
      await dismiss(tester);
      await tester.tap(find.text('Trade'));
      await tester.pumpAndSettle();
      expect(find.byType(FocusHint), findsNothing);
      await tester.tap(find.text('Realm'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show first-time hints again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show first-time hints again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gameplay-hint-realm')), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('gameplay_hints_seen_v1'), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final kind in TacticalKind.values) {
    testWidgets('${kind.name} response hint belongs to the responder', (
      tester,
    ) async {
      final base = tableWithSupplies();
      final players = base.players.toList();
      players[0] = players[0].copyWith(
        cards: [const HeldCard(StrategyDeck.governance, 0)],
      );
      final state = base.copyWith(
        players: players,
        tactical: TacticalWindow(7, kind, 0, [
          1,
        ], card: const PlayStrategyCard(0)),
      );
      await showMatch(tester, state, seat: 0);
      expect(find.byType(FocusHint), findsNothing);
      await showMatch(tester, state, seat: 1);
      expect(
        find.byKey(ValueKey('gameplay-hint-response_${kind.name}')),
        findsOneWidget,
      );
      await dismiss(tester);
      expect(find.byType(FocusHint), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('observers and other players do not receive local turn hints', (
    tester,
  ) async {
    final state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 13);
    await showMatch(tester, state, observing: true);
    expect(find.byType(FocusHint), findsNothing);
    await showMatch(tester, state, seat: 1);
    expect(find.byType(FocusHint), findsNothing);
  });

  testWidgets(
    'hint pauses the local turn timer and respects the master switch',
    (tester) async {
      final events = <MatchEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MatchView(state: tableWithSupplies(), onEvent: events.add),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FocusHint), findsOneWidget);
      await tester.pump(const Duration(seconds: 95));
      expect(events, isEmpty);
      await tester.pumpWidget(const SizedBox());
      SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
      await showMatch(tester, MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 13));
      expect(find.byType(FocusHint), findsNothing);
    },
  );
}
