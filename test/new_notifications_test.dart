import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_activity.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/trade_market.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );

  MatchState capitalState() =>
      MatchEngine.newGame(['You', 'Bob', 'Sue'], 171).copyWith(
        phase: MatchPhase.actions,
        sites: {
          0: const Site(0, Structure.capital),
          1: const Site(1, Structure.town),
        },
      );

  testWidgets(
    'local city loss gets dramatic warning before simultaneous rival loss',
    (tester) async {
      final before = capitalState();
      final after = before.copyWith(
        sites: {
          0: const Site(0, Structure.town),
          1: const Site(1, Structure.village),
        },
        invasions: before.invasions + 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MatchView(state: before, visibleSeat: 0, onEvent: (_) {}),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: MatchView(state: after, visibleSeat: 0, onEvent: (_) {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 430));
      expect(find.byKey(const ValueKey('city-fall-animation')), findsOneWidget);
      expect(find.text('YOUR CITY HAS FALLEN!'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('rival-city-fall-animation')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rival loss is a small humorous toast, never the local catastrophe',
    (tester) async {
      final before = capitalState();
      final after = before.copyWith(
        sites: {
          0: const Site(0, Structure.capital),
          1: const Site(1, Structure.village),
        },
        invasions: before.invasions + 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MatchView(state: before, visibleSeat: 0, onEvent: (_) {}),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: MatchView(state: after, visibleSeat: 0, onEvent: (_) {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 430));
      expect(
        find.byKey(const ValueKey('rival-city-fall-animation')),
        findsOneWidget,
      );
      expect(find.text('Bob lost a city!'), findsOneWidget);
      expect(find.byKey(const ValueKey('city-fall-animation')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('accepted broadcast loudly confirms the deal to proposer', (
    tester,
  ) async {
    final fresh = MatchEngine.newGame([
      'You',
      'Bob',
      'Sue',
    ], 71).copyWith(phase: MatchPhase.actions);
    final players = fresh.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wood: 2});
    players[1] = players[1].copyWith(stores: {Resource.wheat: 1});
    final before = MatchEngine.apply(
      fresh.copyWith(players: players),
      const ProposeTrade(-1, Resource.wood, 1, Resource.wheat, 1),
    );
    final after = MatchEngine.apply(
      before,
      RespondTrade(1, true, offerId: before.offers.single.id),
    );
    Widget activity(MatchState state) => MaterialApp(
      home: Scaffold(body: MatchActivity(state: state, viewerSeat: 0)),
    );
    await tester.pumpWidget(activity(before));
    await tester.pump();
    await tester.pumpWidget(activity(after));
    await tester.pump(const Duration(milliseconds: 410));
    expect(find.text('YOUR TRADE WAS ACCEPTED!'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TradeMarket(
            state: after,
            viewerSeat: 0,
            computerSeats: const {},
            allowOffers: false,
            onEvent: (_) {},
            onOffer: () {},
            onBank: () {},
            onCounter: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('trade-result')), findsOneWidget);
    expect(find.textContaining('accepted the trade'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
