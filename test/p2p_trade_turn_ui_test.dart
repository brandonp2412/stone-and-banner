import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

MatchState botOffersHuman() {
  var state = tableWithSupplies().copyWith(active: 1);
  final players = state.players.toList();
  players[0] = players[0].copyWith(
    stores: {...players[0].stores, Resource.wool: 3},
  );
  players[1] = players[1].copyWith(
    stores: {...players[1].stores, Resource.wood: 3},
  );
  state = state.copyWith(players: players);
  return MatchEngine.apply(
    state,
    const ProposeTrade(0, Resource.wood, 1, Resource.wool, 1),
  );
}

void main() {
  testWidgets('off-turn trade reply never enables End turn on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = botOffersHuman();
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: state,
            online: true,
            viewingSeat: 0,
            observing: true,
            tradeReplyAllowed: true,
            computerSeats: const {1},
            onEvent: events.add,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsOneWidget);
    expect(find.text('Resume computer'), findsNothing);
    expect(find.text('Done').hitTestable(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dismiss-incoming-trade')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsNothing);
    await tester.tap(find.text('Trade').first);
    await tester.pump();
    final offerId = state.offers.single.id;
    final decline = find.byKey(ValueKey('decline-offer-$offerId'));
    final counter = find.byKey(ValueKey('counter-offer-$offerId'));
    final create = find.byKey(const ValueKey('create-player-offer'));
    expect(decline, findsOneWidget);
    expect(tester.widget<OutlinedButton>(decline).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(counter).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    await tester.ensureVisible(decline);
    await tester.tap(decline);
    expect(events, hasLength(1));
    expect(events.single, isA<RespondTrade>());
    expect(find.text('Done').hitTestable(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile observing player may decline but not end bot turn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = botOffersHuman();
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: state,
            online: true,
            viewingSeat: 0,
            observing: true,
            tradeReplyAllowed: true,
            computerSeats: const {1},
            onEvent: events.add,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dismiss-incoming-trade')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('restore-bot-trade')), findsNothing);
    await tester.tap(find.text('Actions').first);
    await tester.pump();
    await tester.tap(find.text('Trade').first);
    await tester.pump();
    final decline = find.byKey(
      ValueKey('decline-offer-${state.offers.single.id}'),
    );
    expect(decline, findsOneWidget);
    await tester.ensureVisible(decline);
    await tester.pumpAndSettle();
    expect(decline.hitTestable(), findsOneWidget);
    await tester.tap(decline);
    expect(events, hasLength(1));
    expect(events.single, isA<RespondTrade>());
    expect(find.text('Resume computer'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
