import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';
import 'package:stone_and_banner/ui/dice_roll.dart';
import 'package:stone_and_banner/ui/match_activity.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

MatchState publicView(MatchState game) =>
    RoomProtocol.readView(RoomProtocol.view(game, 0));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
  });

  testWidgets('incoming multiplayer roll produces the animated dice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final host = MatchEngine.newGame(['Host', 'Bot', 'Guest'], 128);
    final before = publicView(host);
    final after = publicView(
      host.copyWith(phase: MatchPhase.actions, events: [const RollDice(3, 4)]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(
          state: before,
          online: true,
          viewingSeat: 0,
          computerSeats: const {1},
          onEvent: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(
          state: after,
          online: true,
          viewingSeat: 0,
          computerSeats: const {1},
          onEvent: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byType(DiceRoll),
      findsOneWidget,
      reason: 'The network event stream must drive dice animations',
    );
  });

  testWidgets('a remotely accepted trade shows its success reaction', (
    tester,
  ) async {
    final initial = MatchEngine.newGame([
      'Host',
      'Bot',
      'Guest',
    ], 271).copyWith(phase: MatchPhase.actions);
    final players = initial.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wood: 2});
    players[1] = players[1].copyWith(stores: {Resource.wheat: 2});
    final ready = initial.copyWith(players: players);
    final offered = MatchEngine.apply(
      ready,
      const ProposeTrade(-1, Resource.wood, 1, Resource.wheat, 1),
    );
    final accepted = MatchEngine.apply(
      offered,
      RespondTrade(1, true, offerId: offered.offers.single.id),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchActivity(
            state: publicView(offered),
            viewerSeat: 0,
            computerSeats: const {1},
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchActivity(
            state: publicView(accepted),
            viewerSeat: 0,
            computerSeats: const {1},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.textContaining('TRADE WAS ACCEPTED'), findsOneWidget);
  });
}
