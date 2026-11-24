import 'resource_label_finder.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/strategy_hand.dart';

import 'strategy_cards_widget_test.dart' show withCard;

void main() {
  testWidgets('cards stay visible through roll and event phases', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final initial = withCard('forecast');
    final events = <MatchEvent>[];
    Widget view(MatchState state) => MaterialApp(
      home: Scaffold(
        body: MatchView(state: state, visibleSeat: 0, onEvent: events.add),
      ),
    );
    await tester.pumpWidget(view(initial));
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    final cardRect = tester.getRect(find.text('Forecast'));
    for (final phase in [
      MatchPhase.roll,
      MatchPhase.bandit,
      MatchPhase.actions,
    ]) {
      await tester.pumpWidget(view(initial.copyWith(phase: phase)));
      await tester.pumpAndSettle();
      expect(find.byType(StrategyHand), findsOneWidget);
      expect(tester.getRect(find.text('Forecast')), cardRect);
      await tester.tap(find.text('Forecast'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.textContaining('Study the next harvest'),
        ),
        findsOneWidget,
      );
      final discard = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Discard this card'),
      );
      expect(discard.onPressed != null, phase == MatchPhase.actions);
      expect(
        resourceLabel('Collect 1 wood'),
        phase == MatchPhase.actions ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.byTooltip('Close card'));
      await tester.pumpAndSettle();
    }
    expect(events, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sidebar keeps your hand and position across opponent turns', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final initial = withCard('forecast');
    Widget view(MatchState state) => MaterialApp(
      home: Scaffold(
        body: MatchView(
          state: state,
          visibleSeat: 0,
          observing: state.active != 0,
          onEvent: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(view(initial));
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(ListView).first);
    final opponent = initial.copyWith(active: 1);
    await tester.pumpWidget(view(opponent));
    await tester.pumpAndSettle();
    final hand = tester.widget<StrategyHand>(find.byType(StrategyHand));
    expect(hand.state.current.cards, initial.players[0].cards);
    expect(hand.state.active, 0);
    expect(tester.getRect(find.byType(ListView).first), before);
    expect(find.byKey(const PageStorageKey('panel-2')), findsOneWidget);
    await tester.tap(find.text('Realm'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const PageStorageKey('panel-3')),
      findsOneWidget,
      reason: 'Desktop tabs remain navigable on another player’s turn',
    );
    expect(find.text('Town Developments'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('quick-innovation-development')),
          )
          .onPressed,
      isNull,
      reason: 'Viewing the realm cannot grant off-turn development actions',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
