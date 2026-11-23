import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/ai_cards.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;
import 'resource_discard_test.dart' show seven;

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );

  test('multiple bank trades transfer exactly both bundles over the wire', () {
    final fresh = MatchEngine.newGame([
      'A',
      'B',
      'C',
    ], 71).copyWith(phase: MatchPhase.actions);
    final players = fresh.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wood: 16});
    final state = fresh.copyWith(players: players);
    final rate = MatchEngine.tradeRate(state, 0, Resource.wood);
    final event = const BankExchange(Resource.wood, Resource.wheat, times: 3);
    final wire = RoomProtocol.eventFromJson(event.toJson()) as BankExchange;
    expect(wire.times, 3);
    expect(event.toJson()['times'], 3);
    expect(
      const BankExchange(
        Resource.wood,
        Resource.wheat,
      ).toJson().containsKey('times'),
      isFalse,
    );
    final result = MatchEngine.apply(state, wire);
    expect(result.players[0].stores[Resource.wood], 16 - 3 * rate);
    expect(result.players[0].stores[Resource.wheat], 3);
    expect(result.bank[Resource.wood], state.bank[Resource.wood]! + rate * 3);
    expect(result.bank[Resource.wheat], state.bank[Resource.wheat]! - 3);
    expect(
      () => MatchEngine.apply(
        state,
        const BankExchange(Resource.wood, Resource.wheat, times: 100),
      ),
      throwsStateError,
    );
  });

  test('bot accepts exceptionally generous three-for-one bundle', () {
    final fresh = MatchEngine.newGame([
      'A',
      'B',
      'C',
    ], 71).copyWith(phase: MatchPhase.actions);
    final players = fresh.players.toList();
    players[0] = players[0].copyWith(
      stores: {Resource.brick: 2, Resource.ore: 1},
    );
    players[1] = players[1].copyWith(stores: {Resource.wheat: 1});
    var state = fresh.copyWith(players: players);
    state = MatchEngine.apply(
      state,
      const ProposeTrade(
        1,
        Resource.brick,
        2,
        Resource.wheat,
        1,
        giveBundle: {Resource.brick: 2, Resource.ore: 1},
        wantBundle: {Resource.wheat: 1},
      ),
    );
    final view = AiActionAdapter.observe(state.copyWith(active: 1), 1);
    final decision = AiCardStrategy.incomingOffer(view);
    expect(decision, isA<RespondTrade>());
    expect((decision as RespondTrade).accept, isTrue);
    final after = MatchEngine.apply(state, decision);
    expect(after.players[1].stores[Resource.wheat], 0);
    expect(after.players[1].stores[Resource.brick], 2);
    expect(after.players[1].stores[Resource.ore], 1);
  });

  testWidgets('bank quantity and trade composer restore keep draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fresh = tableWithSupplies();
    final players = fresh.players.toList();
    players[fresh.active] = fresh.current.copyWith(
      stores: {for (final good in Resource.values) good: 0, Resource.wood: 16},
    );
    final state = fresh.copyWith(players: players);
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(state: state, onEvent: events.add),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ResourceIcon).first);
    await tester.pumpAndSettle();
    expect(find.text('Exchanges'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bank-bundles-plus')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bank-bundle-count')), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('minimize-trade-composer')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('restore-trade-composer')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('restore-trade-composer')));
    await tester.pumpAndSettle();
    expect(find.text('Exchanges'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Exchange'));
    await tester.pumpAndSettle();
    expect(events.whereType<BankExchange>().single.times, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('discard later restores the selected hand', (tester) async {
    final before = seven();
    final (a, b) = MatchEngine.expectedDice(before);
    final state = MatchEngine.apply(before, RollDice(a, b));
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(state: state, onEvent: events.add),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-DISCARD-add-wheat')));
    await tester.pump();
    expect(find.text('1 / 4 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('minimize-discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('restore-discard')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore-discard')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 4 selected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
