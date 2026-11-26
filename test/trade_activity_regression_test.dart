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
  for (final size in [const Size(393, 852), const Size(844, 390)]) {
    testWidgets('bot activity stays quiet during fast-forward at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var state = nextActionTurn(funded());
      Future<void> show({bool skipping = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MatchView(
                state: state,
                onEvent: (_) {},
                computerSeats: const {1},
                visibleSeat: 0,
                fastForwardingBots: skipping,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 450));
      }

      final notice = find.textContaining('visits the market');
      await show();
      state = MatchEngine.apply(
        state,
        const BankExchange(Resource.wood, Resource.wheat),
      );
      await show();
      expect(notice, findsOneWidget);

      await show(skipping: true);
      expect(notice, findsNothing);
      state = MatchEngine.apply(
        state,
        const BankExchange(Resource.brick, Resource.wheat),
      );
      await show(skipping: true);
      expect(notice, findsNothing);

      state = MatchEngine.apply(
        state,
        const BankExchange(Resource.wool, Resource.wheat),
      );
      await show();
      expect(notice, findsNothing);
      state = MatchEngine.apply(
        state,
        const BankExchange(Resource.ore, Resource.wheat),
      );
      await show();
      expect(notice, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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

  testWidgets('human-only or declined-bot offers are awaiting a reply', (
    tester,
  ) async {
    Future<void> show(TradeProposal offer, Set<int> bots) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TradeMarket(
              state: funded().copyWith(offers: [offer]),
              computerSeats: bots,
              viewerSeat: 0,
              onBank: () {},
              onOffer: () {},
              onCounter: (_) {},
              onEvent: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await show(
      const TradeProposal(1, 0, 1, Resource.wood, 1, Resource.brick, 1),
      {2},
    );
    expect(find.text('Your offer is awaiting a reply.'), findsOneWidget);
    expect(find.text('YOUR PENDING OFFER'), findsOneWidget);
    await show(
      const TradeProposal(2, 0, -1, Resource.wood, 1, Resource.brick, 1),
      {},
    );
    expect(find.text('Your offer is awaiting a reply.'), findsOneWidget);
    await show(
      const TradeProposal(
        3,
        0,
        -1,
        Resource.wood,
        1,
        Resource.brick,
        1,
        declinedBy: {2},
      ),
      {2},
    );
    expect(find.text('Your offer is awaiting a reply.'), findsOneWidget);
    await show(
      const TradeProposal(4, 0, -1, Resource.wood, 1, Resource.brick, 1),
      {2},
    );
    expect(find.text('Thinking about your offer…'), findsOneWidget);
    expect(find.text('CONSIDERING YOUR OFFER'), findsOneWidget);
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

  testWidgets('AI theft uses board animation without a duplicate toast', (
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
    expect(find.text('CHEEKY MOVE'), findsNothing);
    expect(find.textContaining('eyes your goods'), findsNothing);
    expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
