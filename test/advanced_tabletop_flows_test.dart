import 'action_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'strategy_cards_test.dart' as fixtures;
import 'stage5_reactions_test.dart' as reactions;

void main() {
  for (final scale in [1.0, 1.6]) {
    for (final response in [
      'Counter: Boundary Dispute',
      'Pass',
      'Skip / timeout fallback',
    ]) {
      testWidgets('Governance $response at scale $scale', (tester) async {
        tester.view.physicalSize = scale == 1
            ? const Size(640, 320)
            : const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var state = reactions.grant(
          reactions.draft(109).copyWith(phase: MatchPhase.actions),
          1,
          Resource.ore,
          2,
        );
        state = reactions.equip(
          reactions.equip(state, 0, 'political-pressure'),
          1,
          'boundary-dispute',
        );
        state = MatchEngine.apply(
          state,
          MatchEngine.legalCardPlays(
            state,
            0,
          ).firstWhere((e) => e.target == 1 && e.receive == Resource.ore),
        );
        final originalOre = state.players[1].stores[Resource.ore]!;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              fontFamily: 'NotoSans',
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, refresh) => MatchView(
                  state: state,
                  onEvent: (event) =>
                      refresh(() => state = MatchEngine.apply(state, event)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Governance challenge'), findsOneWidget);
        expect(find.text('Private hands are concealed'), findsNothing);
        await tester.scrollUntilVisible(
          find.text(response),
          80,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(response));
        await tester.pumpAndSettle();
        expect(state.tactical, isNull);
        expect(
          state.players[1].stores[Resource.ore],
          originalOre - (response.startsWith('Counter:') ? 0 : 1),
        );
        expect(state.players[0].cards, isEmpty);
        expect(
          state.players[1].cards.length,
          response.startsWith('Counter:') ? 0 : 1,
        );
        reactions.conserved(state);
        expect(tester.takeException(), isNull);
      });
    }
    for (final action in {
      'Fortify': 'fortify',
      'Recruit Knight': 'recruit',
      'Activate Knight': 'activate',
      'Upgrade Knight': 'promote',
      'Move Knight': 'knightMove',
    }.entries) {
      testWidgets('${action.key} through the tabletop at scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = scale == 1
            ? const Size(640, 320)
            : const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final initial = fixtures.prepared();
        var state = initial;
        final accepted = <MatchEvent>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              fontFamily: 'NotoSans',
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, refresh) => MatchView(
                  state: state,
                  onEvent: (event) {
                    accepted.add(event);
                    refresh(() => state = MatchEngine.apply(state, event));
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final map = tester.getRect(find.byKey(const ValueKey('realm-map')));
        await tester.tap(find.text('Actions'));
        await tester.pumpAndSettle();
        await scrollToAction(tester, 'Road');
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Knights & Defense'),
          80,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Knights & Defense'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(action.key),
          80,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(action.key));
        await tester.pumpAndSettle();
        for (
          var step = 0;
          step < (action.key == 'Move Knight' ? 2 : 1);
          step++
        ) {
          await tester.tap(find.byTooltip('Choose board target from list'));
          await tester.pumpAndSettle();
          final targets = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(ListTile),
          );
          expect(targets, findsWidgets);
          await Scrollable.ensureVisible(
            tester.element(targets.first),
            alignment: .1,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
          await tester.pumpAndSettle();
          tester.widget<ListTile>(targets.first).onTap!();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(accepted.single.toJson()['type'], action.value);
        expect(tester.getRect(find.byKey(const ValueKey('realm-map'))), map);
        fixtures.checkConservation(state);
        expect(
          MatchEngine.snapshot(state),
          MatchEngine.snapshot(MatchEngine.apply(initial, accepted.single)),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
