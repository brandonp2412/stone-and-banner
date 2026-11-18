import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/trade_feedback.dart';
import 'package:stone_and_banner/ui/trade_market.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

MatchState funded() {
  final state = tableWithSupplies();
  final players = state.players.toList();
  for (var i = 1; i < players.length; i++) {
    final stores = Map<Resource, int>.of(players[i].stores);
    for (final resource in Resource.values) {
      stores[resource] = (stores[resource] ?? 0) + 4;
    }
    players[i] = players[i].copyWith(stores: stores);
  }
  return state.copyWith(players: players);
}

MatchState nextActionTurn(MatchState state) => MatchEngine.apply(
  state,
  const EndTurn(),
).copyWith(phase: MatchPhase.actions);

void main() {
  test('bot-to-bot decline never claims the human made an offer', () {
    var s = nextActionTurn(funded()); // Ben
    s = MatchEngine.apply(
      s,
      const ProposeTrade(2, Resource.wood, 1, Resource.brick, 1),
    );
    final id = s.offers.single.id;
    s = nextActionTurn(s); // Cora
    s = MatchEngine.apply(s, RespondTrade(2, false, offerId: id));
    expect(latestTradeFeedback(s), contains('declined'));
    expect(latestTradeFeedback(s, viewer: 0), isNull);
    expect(latestTradeFeedback(s, viewer: 1), contains('declined'));
    expect(latestTradeFeedback(s, viewer: 2), contains('declined'));
  });

  test('offers can be countered more than once without holding goods', () {
    var s = funded();
    s = MatchEngine.apply(
      s,
      const ProposeTrade(1, Resource.wood, 1, Resource.brick, 1),
    );
    final first = s.offers.single;
    final woodHeld = s.players[0].stores[Resource.wood]!;
    s = nextActionTurn(s); // Ben
    s = MatchEngine.apply(
      s,
      ProposeTrade(0, Resource.brick, 2, Resource.wood, 1, counterOf: first.id),
    );
    final second = s.offers.single;
    expect(second.isCounter, isTrue);
    expect(s.players[0].stores[Resource.wood], woodHeld);
    s = nextActionTurn(s); // Cora
    s = nextActionTurn(s); // Dee
    s = nextActionTurn(s); // Ada
    s = MatchEngine.apply(
      s,
      ProposeTrade(
        1,
        Resource.wood,
        2,
        Resource.brick,
        2,
        counterOf: second.id,
      ),
    );
    expect(s.offers.single.isCounter, isTrue);
    expect(s.offers.single.proposer, 0);
    expect(s.offers.single.target, 1);
    expect(s.offers.length, 1);
  });

  testWidgets('incoming offer provides accept, decline, counter actions', (
    tester,
  ) async {
    var s = funded();
    s = MatchEngine.apply(
      s,
      const ProposeTrade(1, Resource.wood, 1, Resource.brick, 1),
    );
    s = nextActionTurn(s);
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: TradeMarket(
            state: s,
            viewerSeat: 1,
            onBank: () {},
            onOffer: () {},
            onCounter: (_) {},
            onEvent: events.add,
          ),
        ),
      ),
    );
    expect(find.text('NEEDS YOUR ANSWER'), findsOneWidget);
    expect(
      find.byKey(ValueKey('accept-offer-${s.offers.single.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('counter-offer-${s.offers.single.id}')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(ValueKey('decline-offer-${s.offers.single.id}')),
    );
    expect(events.single, isA<RespondTrade>());
    expect((events.single as RespondTrade).accept, isFalse);
  });

  testWidgets('AI robbery produces a cheeky notice instead of a trade popup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(750, 450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = funded().copyWith(active: 1);
    final after = before.copyWith(
      events: [...before.events, const MoveBandit(0, victim: 0)],
    );
    Widget app(MatchState s) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: MatchView(
          state: s,
          onEvent: (_) {},
          observing: true,
          visibleSeat: 0,
          computerSeats: const {1, 2, 3},
        ),
      ),
    );
    await tester.pumpWidget(app(before));
    await tester.pumpWidget(app(after));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('CHEEKY MOVE'), findsOneWidget);
    expect(find.textContaining('eyes your goods'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
