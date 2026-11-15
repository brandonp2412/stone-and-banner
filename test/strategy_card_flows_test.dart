import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/strategy_hand.dart';
import 'package:stone_and_banner/ui/labels.dart';

import 'strategy_cards_test.dart' as fixtures;

void main() {
  for (final scale in [1.0, 1.6]) {
    for (final card in StrategyCards.definitions) {
      testWidgets('${card.name}: choose and confirm at text scale $scale', (
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
        await (FontLoader('NotoSans')
              ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf')))
            .load();
        final initial = fixtures.holding(fixtures.prepared(), card);
        final accepted = <MatchEvent>[];
        var state = initial;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              fontFamily: 'NotoSans',
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, refresh) => SingleChildScrollView(
                  child: StrategyHand(
                    state: state,
                    onEvent: (event) {
                      accepted.add(event);
                      refresh(() => state = MatchEngine.apply(state, event));
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(card.name));
        await tester.pumpAndSettle();
        final option = MatchEngine.legalCardPlays(initial, 0).first;
        final targetLabel = switch (card.power) {
          CardPower.freeRoad => 'Build road on edge ${option.vertex! + 1}',
          CardPower.freeFort => 'Fortify junction ${option.vertex! + 1}',
          CardPower.activate =>
            'Activate Knight at junction ${option.vertex! + 1}',
          CardPower.promote =>
            'Promote Knight at junction ${option.vertex! + 1}',
          CardPower.exhaust =>
            'Stand down rival Knight at junction ${option.vertex! + 1}',
          CardPower.moveBandit =>
            'Move Bandit to hex ${option.tile! + 1} '
                '(${terrainLabel(initial.board.tiles[option.tile!].land)})',
          _ => null,
        };
        if (targetLabel != null) expect(find.text(targetLabel), findsOneWidget);
        final confirm = find.widgetWithText(FilledButton, 'Play selected card');
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        expect(accepted, isEmpty);
        // Exchanges and raids first choose a resource or rival, then a target.
        for (
          var step = 0;
          step < 2 && tester.widget<FilledButton>(confirm).onPressed == null;
          step++
        ) {
          final choices = find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(ListTile),
          );
          expect(choices, findsWidgets);
          await tester.tap(choices.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
        expect(confirm.hitTestable(), findsOneWidget);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(accepted.single, isA<PlayStrategyCard>());
        expect(state.current.cards, isEmpty);
        expect(find.byType(Dialog), findsNothing);
        fixtures.checkConservation(state);
        fixtures.checkCards(state);
        expect(
          MatchEngine.snapshot(state),
          MatchEngine.snapshot(MatchEngine.apply(initial, accepted.single)),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
