import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/ai_turn_coordinator.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

MatchState fundedGame() {
  final fresh = MatchEngine.newGame([
    'Human',
    'Bob',
    'Alice',
  ], 95).copyWith(phase: MatchPhase.actions);
  final players = fresh.players.toList();
  players[0] = players[0].copyWith(stores: {Resource.wood: 3});
  players[1] = players[1].copyWith(stores: {Resource.wheat: 2});
  players[2] = players[2].copyWith(stores: {Resource.wheat: 2});
  return fresh.copyWith(players: players);
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );

  test(
    'broadcast declines are per seat; first acceptance executes one trade',
    () {
      final original = fundedGame();
      final action = const ProposeTrade(
        -1,
        Resource.wood,
        1,
        Resource.wheat,
        1,
      );
      final wire = RoomProtocol.eventFromJson(action.toJson()) as ProposeTrade;
      expect(wire.target, -1);
      final offered = MatchEngine.apply(original, wire);
      final id = offered.offers.single.id;
      expect(offered.offers.single.canRespond(1), true);
      expect(offered.offers.single.canRespond(2), true);
      expect(AiTurnCoordinator.actingSeat(offered, (seat) => seat != 0), 1);

      final declined = MatchEngine.apply(
        offered,
        RespondTrade(1, false, offerId: id),
      );
      expect(declined.offers, hasLength(1));
      expect(declined.offers.single.declinedBy, {1});
      expect(declined.offers.single.canRespond(1), false);
      expect(declined.offers.single.canRespond(2), true);
      expect(AiTurnCoordinator.actingSeat(declined, (seat) => seat != 0), 2);
      final remote = RoomProtocol.readView(RoomProtocol.view(declined, 2));
      expect(remote.offers.single.declinedBy, {1});

      final accepted = MatchEngine.apply(
        declined,
        RespondTrade(2, true, offerId: id),
      );
      expect(accepted.offers, isEmpty);
      expect(accepted.players[0].stores[Resource.wood], 2);
      expect(accepted.players[0].stores[Resource.wheat], 1);
      expect(accepted.players[1].stores[Resource.wheat], 2);
      expect(accepted.players[2].stores[Resource.wheat], 1);
      expect(accepted.players[2].stores[Resource.wood], 1);
      expect(
        () => MatchEngine.apply(accepted, RespondTrade(1, true, offerId: id)),
        throwsStateError,
      );

      final allDeclined = MatchEngine.apply(
        declined,
        RespondTrade(2, false, offerId: id),
      );
      expect(allDeclined.offers, isEmpty);
      expect(allDeclined.players[0].stores, original.players[0].stores);
    },
  );

  test(
    'any invited seat can counter a broadcast; reply belongs to counterer',
    () {
      var state = MatchEngine.apply(
        fundedGame(),
        const ProposeTrade(-1, Resource.wood, 1, Resource.wheat, 1),
      );
      final originalId = state.offers.single.id;
      const response = ProposeTrade(
        0,
        Resource.wheat,
        1,
        Resource.wood,
        1,
        counterOf: 0,
        counterActor: 1,
      );
      final decoded =
          RoomProtocol.eventFromJson(response.toJson()) as ProposeTrade;
      expect(decoded.counterActor, 1);
      state = MatchEngine.apply(state, decoded);
      expect(state.offers.single.proposer, 1);
      expect(state.offers.single.target, 0);
      expect(state.offers.single.isCounter, true);
      expect(state.offers.single.id, isNot(originalId));
      state = MatchEngine.apply(
        state,
        RespondTrade(0, true, offerId: state.offers.single.id),
      );
      expect(state.offers, isEmpty);
      expect(state.players[1].stores[Resource.wood], 1);
      expect(state.players[1].stores[Resource.wheat], 1);
      expect(state.players[0].stores[Resource.wheat], 1);
    },
  );

  test('computer broadcast reserves human reply window before other bots', () {
    var game = fundedGame().copyWith(active: 1);
    game = MatchEngine.apply(
      game,
      const ProposeTrade(-1, Resource.wheat, 1, Resource.wood, 1),
    );
    expect(
      AiTurnCoordinator.actingSeat(game, (seat) => seat != 0),
      game.active,
      reason:
          'The host holds a bounded human-response window before bots reply',
    );
    final view = AiActionAdapter.observe(game.copyWith(active: 2), 2);
    expect(view.legalActions.whereType<RespondTrade>().isNotEmpty, true);
  });

  testWidgets(
    'player offer defaults to everyone; specific player is optional',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = tableWithSupplies();
      final events = <MatchEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MatchView(
            state: state,
            visibleSeat: state.active,
            onEvent: events.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trade').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-player-offer')));
      await tester.pumpAndSettle();
      final selector = find.byType(DropdownButton<int>);
      expect(selector, findsOneWidget);
      expect(tester.widget<DropdownButton<int>>(selector).value, -1);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('To everyone'), findsWidgets);
      await tester.tap(find.text('To everyone').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send offer'));
      await tester.pumpAndSettle();
      expect(events.whereType<ProposeTrade>().single.target, -1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
