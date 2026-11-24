import 'resource_label_finder.dart';

import 'dart:ui' show SemanticsAction;

import 'action_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

MatchState withCard(String id) {
  var s = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 46);
  for (var i = 0; i < 6; i++) {
    s = MatchEngine.apply(s, PlaceVillage(MatchEngine.legalVertices(s).first));
    s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
  }
  final track = StrategyCards.definitions.firstWhere((c) => c.id == id).track;
  final index = StrategyCards.deck(track).indexWhere((c) => c.id == id);
  final pile = List<int>.of(s.drawPiles[track]!)..remove(index);
  final players = s.players.toList();
  players[0] = players[0].copyWith(cards: [HeldCard(track, index)]);
  return s.copyWith(
    players: players,
    drawPiles: {...s.drawPiles, track: pile},
    phase: MatchPhase.actions,
  );
}

void main() {
  for (final size in [const Size(844, 390), const Size(1280, 800)]) {
    testWidgets(
      'held cards remain visible but cannot be played before rolling at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final events = <MatchEvent>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MatchView(
                state: withCard('forecast').copyWith(phase: MatchPhase.roll),
                onEvent: events.add,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (size.width < 900) {
          await tester.tap(find.text('Actions'));
          await tester.pumpAndSettle();
          await scrollToAction(tester, 'Cards');
        } else {
          await tester.tap(find.text('Cards'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Forecast'), findsOneWidget);
        await tester.ensureVisible(find.text('Forecast'));
        await tester.tap(find.text('Forecast'));
        await tester.pumpAndSettle();
        expect(find.text('No legal play right now.'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Play selected card'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Discard this card'),
              )
              .onPressed,
          isNull,
        );
        expect(events, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('card row is one named accessible button', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(state: withCard('forecast'), onEvent: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    final card = find.widgetWithText(OutlinedButton, 'Forecast');
    expect(card, findsOneWidget);
    final node = tester.getSemantics(card);
    expect(node.label, contains('Forecast'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
      find.descendant(of: card, matching: find.byType(IconButton)),
      findsNothing,
    );
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(resourceLabel('Collect 1 wood'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('card detail exposes accessible legal targets and plays card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = withCard('forecast');
    final before = state.current.stores[Resource.wood] ?? 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => MatchView(
              state: state,
              onEvent: (event) => refresh(() {
                state = MatchEngine.apply(state, event);
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Cards');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Strategy hand'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Forecast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forecast'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.textContaining('Study the next harvest'),
      ),
      findsOneWidget,
    );
    await tester.tap(resourceLabel('Collect 1 wood'));
    await tester.pumpAndSettle();
    expect(state.current.cards, hasLength(1), reason: 'Selection is not play');
    await tester.tap(find.text('Play selected card'));
    await tester.pumpAndSettle();
    expect(state.current.cards, isEmpty);
    expect(state.current.stores[Resource.wood], before + 1);
  });

  testWidgets('unplayable card remains dismissible and discardable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final base = withCard('fortification-plans');
    var state = base.copyWith(fortified: base.sites.keys.toSet());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => MatchView(
              state: state,
              onEvent: (event) => refresh(() {
                state = MatchEngine.apply(state, event);
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Cards');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Strategy hand'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fortification Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fortification Plans'));
    await tester.pumpAndSettle();
    expect(find.text('No legal play right now.'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Play selected card'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Discard this card'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this card?'), findsOneWidget);
    await tester.tap(find.text('Keep card'));
    await tester.pumpAndSettle();
    expect(state.current.cards, hasLength(1));
    await tester.tap(find.text('Discard this card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard', skipOffstage: false).last);
    await tester.pumpAndSettle();
    expect(state.current.cards, isEmpty);
  });

  testWidgets('exchange cards group choices and require confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = withCard('open-routes');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => MatchView(
              state: state,
              onEvent: (event) => refresh(() {
                state = MatchEngine.apply(state, event);
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Cards');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Strategy hand'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open Routes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Routes'));
    await tester.pumpAndSettle();
    expect(find.text('Choose what to give'), findsOneWidget);
    final group = resourceLabel('Give 1 ', contains: true).first;
    await tester.tap(group);
    await tester.pumpAndSettle();
    expect(find.text('Choose a legal target or exchange'), findsOneWidget);
    await tester.tap(resourceLabel('receive 1 ', contains: true).first);
    await tester.pumpAndSettle();
    expect(state.current.cards, hasLength(1));
    await tester.tap(find.text('Play selected card'));
    await tester.pumpAndSettle();
    expect(state.current.cards, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
