import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';
import 'package:stone_and_banner/network/room_host.dart';
import 'package:stone_and_banner/ui/match_activity.dart';
import 'package:stone_and_banner/ui/trade_market.dart';

void main() {
  MatchState initial() =>
      MatchEngine.newGame(['Host', 'Guest', 'Bot One', 'Bot Two'], 9876);

  test('new matches schedule a raid at exactly six completed rounds', () {
    var game = initial().copyWith(phase: MatchPhase.actions);
    expect(game.raidInterval, 6);
    for (var turn = 1; turn <= 24; turn++) {
      game = MatchEngine.apply(
        game.copyWith(phase: MatchPhase.actions),
        const EndTurn(),
      );
      expect(game.reaverPressure, turn ~/ 4);
      if (turn < 24) {
        expect(game.phase, MatchPhase.roll);
      } else {
        expect(game.phase, MatchPhase.invasion);
      }
    }
  });

  test('a seven does not accelerate the six-round raid', () {
    MatchState? game;
    for (var seed = 1; seed < 100; seed++) {
      final candidate = MatchEngine.newGame([
        'Host',
        'Guest',
        'Bot One',
        'Bot Two',
      ], seed);
      final dice = MatchEngine.expectedDice(candidate);
      if (dice.$1 + dice.$2 == 7) {
        game = candidate.copyWith(phase: MatchPhase.roll);
        break;
      }
    }
    expect(game, isNotNull);
    final dice = MatchEngine.expectedDice(game!);
    final after = MatchEngine.apply(game, RollDice(dice.$1, dice.$2));
    expect(after.phase, MatchPhase.bandit);
    expect(after.reaverPressure, 0);
  });

  test('host and guest complete reciprocal authoritative trades with private hands', () {
    final room = HostedRoom('ABCD1234', 4, 123);
    for (final name in ['Host', 'Guest', 'Bot A', 'Bot B']) {
      room.join(name);
    }
    room.start(0);
    final players = room.state!.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wood: 3});
    players[1] = players[1].copyWith(stores: {Resource.wheat: 3});
    room.state = room.state!.copyWith(
      phase: MatchPhase.actions,
      players: players,
    );
    Map<String, Object?> send(int seat, int i, MatchEvent event) =>
        room.move(seat, 'trade-$i', room.version, event.toJson());
    expect(
      send(
        0,
        0,
        const ProposeTrade(1, Resource.wood, 1, Resource.wheat, 1),
      )['ok'],
      true,
    );
    final guest = RoomProtocol.readView(RoomProtocol.view(room.state!, 1));
    expect(
      guest.players[0].stores[Resource.wood] ?? 0,
      0,
      reason: 'Guest must not see host inventory',
    );
    expect(guest.offers.single.proposer, 0);
    expect(
      send(1, 1, RespondTrade(1, true, offerId: guest.offers.single.id))['ok'],
      true,
    );
    expect(room.state!.players[0].stores[Resource.wheat], 1);
    expect(room.state!.players[1].stores[Resource.wood], 1);
    expect(room.state!.offers, isEmpty);
    room.state = room.state!.copyWith(active: 1, phase: MatchPhase.actions);
    expect(
      send(
        1,
        2,
        const ProposeTrade(0, Resource.wood, 1, Resource.wheat, 1),
      )['ok'],
      true,
    );
    final host = RoomProtocol.readView(RoomProtocol.view(room.state!, 0));
    expect(
      host.players[1].stores[Resource.wood] ?? 0,
      0,
      reason: 'Host client view must not see guest inventory',
    );
    expect(
      send(0, 3, RespondTrade(0, true, offerId: host.offers.single.id))['ok'],
      true,
    );
    expect(room.state!.players[0].stores[Resource.wood], 3);
    expect(room.state!.players[1].stores[Resource.wheat], 3);
  });

  testWidgets('guest can accept when host inventory is intentionally hidden', (
    tester,
  ) async {
    var state = initial();
    final players = state.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wood: 2});
    players[1] = players[1].copyWith(stores: {Resource.wheat: 2});
    state = MatchEngine.apply(
      state.copyWith(phase: MatchPhase.actions, players: players),
      const ProposeTrade(1, Resource.wood, 1, Resource.wheat, 1),
    );
    final received = RoomProtocol.readView(RoomProtocol.view(state, 1));
    expect(received.players[0].stores[Resource.wood], 0);
    MatchEvent? reply;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TradeMarket(
              state: received,
              viewerSeat: 1,
              privateOpponentHands: true,
              onEvent: (event) => reply = event,
              onBank: () {},
              onOffer: () {},
              onCounter: (_) {},
            ),
          ),
        ),
      ),
    );
    final accept = find.byKey(
      ValueKey('accept-offer-${state.offers.single.id}'),
    );
    expect(accept, findsOneWidget);
    expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);
    await tester.tap(accept);
    expect(reply, isA<RespondTrade>());
    expect((reply as RespondTrade).accept, isTrue);
  });

  testWidgets('guest emote identifies the sender without a game move', (
    tester,
  ) async {
    final state = initial();
    Widget view(int serial) => MaterialApp(
      home: MatchActivity(
        state: state,
        viewerSeat: 0,
        emote: '👏',
        emoteSeat: 1,
        emoteSerial: serial,
      ),
    );
    await tester.pumpWidget(view(0));
    await tester.pumpWidget(view(1));
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('👏'), findsOneWidget);
    expect(state.events, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
