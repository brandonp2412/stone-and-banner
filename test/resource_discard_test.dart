import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'advanced_test.dart' show draft;

MatchState seven() {
  var state = draft(55).copyWith(phase: MatchPhase.roll);
  final players = state.players.toList();
  for (var i = 0; i < players.length; i++) {
    players[i] = players[i].copyWith(
      stores: {
        for (final r in Resource.values) r: 0,
        if (i == 0) Resource.wood: 5,
        if (i == 0) Resource.wheat: 4,
      },
    );
  }
  state = state.copyWith(players: players);
  while (true) {
    final (a, b) = MatchEngine.expectedDice(state);
    if (a + b == 7) return state;
    state = state.copyWith(rollCount: state.rollCount + 1);
  }
}

void main() {
  test(
    'seven waits for a validated choice and returns chosen goods to bank',
    () {
      final before = seven();
      final (a, b) = MatchEngine.expectedDice(before);
      final rolled = MatchEngine.apply(before, RollDice(a, b));
      expect(rolled.pendingDiscards, {0: 4});
      expect(rolled.players[0].stores, before.players[0].stores);
      expect(() => MatchEngine.apply(rolled, MoveBandit(0)), throwsStateError);
      for (final goods in [
        {Resource.wood: 3},
        {Resource.wheat: 5, Resource.wood: -1},
        {Resource.ore: 4},
      ]) {
        expect(
          () => MatchEngine.apply(rolled, DiscardResources(0, goods)),
          throwsStateError,
        );
      }
      final event = DiscardResources(0, {Resource.wheat: 4});
      final after = MatchEngine.apply(rolled, event);
      expect(after.pendingDiscards, isEmpty);
      expect(after.players[0].stores[Resource.wood], 5);
      expect(after.players[0].stores[Resource.wheat], 0);
      expect(after.bank[Resource.wheat], rolled.bank[Resource.wheat]! + 4);
      final wire = RoomProtocol.eventFromJson(
        jsonDecode(jsonEncode(event.toJson())),
      );
      expect(wire.toJson(), event.toJson());
      final view = RoomProtocol.readView(RoomProtocol.view(rolled, 0));
      expect(view.pendingDiscards, {0: 4});
      expect(const HeuristicAi().choose(rolled), isA<DiscardResources>());
      final legacy = MatchEngine.apply(
        before,
        RollDice(a, b, chooseDiscards: false),
      );
      expect(legacy.pendingDiscards, isEmpty);
      expect(legacy.players[0].stores.values.fold<int>(0, (a, b) => a + b), 5);
    },
  );

  testWidgets('modal requires exact selection and submits chosen resources', (
    tester,
  ) async {
    final before = seven();
    final (a, b) = MatchEngine.expectedDice(before);
    final state = MatchEngine.apply(before, RollDice(a, b));
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(state: state, onEvent: events.add),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Discard 4 resources');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    for (var i = 0; i < 4; i++) {
      await tester.tap(
        find.byKey(const ValueKey('transfer-DISCARD-add-wheat')),
      );
      await tester.pump();
    }
    expect(find.text('4 / 4 selected'), findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect((events.single as DiscardResources).goods, {Resource.wheat: 4});
    await tester.pumpWidget(const SizedBox());
  });
}
