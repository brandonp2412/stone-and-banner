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
  testWidgets('card detail exposes accessible legal targets and plays card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
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
    await tester.scrollUntilVisible(find.textContaining('Strategy hand'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forecast'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Study the next harvest'), findsOneWidget);
    await tester.tap(find.text('Collect 1 wood'));
    await tester.pumpAndSettle();
    expect(state.current.cards, isEmpty);
    expect(state.current.stores[Resource.wood], before + 1);
  });

  testWidgets('unplayable card remains dismissible and discardable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = withCard('fortification-plans');
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
    await tester.scrollUntilVisible(find.textContaining('Strategy hand'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fortification Plans'));
    await tester.pumpAndSettle();
    expect(find.text('No legal play right now.'), findsOneWidget);
    await tester.tap(find.text('Discard this card'));
    await tester.pumpAndSettle();
    expect(state.current.cards, isEmpty);
  });
}
