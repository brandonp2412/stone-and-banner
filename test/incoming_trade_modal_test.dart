import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

MatchState offerFrom(int seat, {int? id}) {
  final original = tableWithSupplies();
  final players = original.players.toList();
  players[0] = players[0].copyWith(
    stores: {...players[0].stores, Resource.wool: 3},
  );
  players[seat] = players[seat].copyWith(
    stores: {...players[seat].stores, Resource.wood: 3},
  );
  final prepared = original.copyWith(
    phase: MatchPhase.actions,
    active: seat,
    players: players,
  );
  if (id != null) {
    return prepared.copyWith(
      offers: [TradeProposal(id, seat, 0, Resource.wood, 1, Resource.wool, 1)],
    );
  }
  return MatchEngine.apply(
    prepared,
    const ProposeTrade(0, Resource.wood, 1, Resource.wool, 1),
  );
}

void main() {
  testWidgets('dismissed offer remains in Trade and new offer pops once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = offerFrom(1);
    late StateSetter refresh;
    final actions = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) {
              refresh = update;
              return MatchView(
                state: state,
                online: true,
                viewingSeat: 0,
                observing: true,
                tradeReplyAllowed: true,
                onEvent: actions.add,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsOneWidget);
    expect(find.text('Trade offer'), findsOneWidget);
    final offerId = state.offers.single.id;
    expect(find.byKey(ValueKey('decline-offer-$offerId')), findsOneWidget);
    expect(find.byKey(const ValueKey('create-player-offer')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dismiss-incoming-trade')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('restore-bot-trade')), findsNothing);
    expect(actions, isEmpty, reason: 'Dismiss does not decline the offer');
    refresh(() => state = state.copyWith(round: state.round + 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsNothing);
    await tester.tap(find.text('Trade').first);
    await tester.pump();
    final decline = find.byKey(ValueKey('decline-offer-$offerId'));
    expect(decline, findsOneWidget);
    expect(tester.widget<OutlinedButton>(decline).onPressed, isNotNull);
    final newId = offerId + 30;
    refresh(() => state = offerFrom(2, id: newId));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('incoming-trade-dialog')),
        matching: find.byKey(ValueKey('decline-offer-$newId')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('decline-offer-$offerId')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dismiss-incoming-trade')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsNothing);
    expect(find.byKey(ValueKey('decline-offer-$newId')), findsOneWidget);
    expect(actions, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('standing offer stays actionable on the recipient own turn', (
    tester,
  ) async {
    final state = offerFrom(1).copyWith(active: 0);
    final actions = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: state,
            online: true,
            viewingSeat: 0,
            observing: false,
            onEvent: actions.add,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsOneWidget);
    final decline = find.byKey(
      ValueKey('decline-offer-${state.offers.single.id}'),
    );
    expect(tester.widget<OutlinedButton>(decline).onPressed, isNotNull);
    await tester.tap(decline);
    expect(actions.single, isA<RespondTrade>());
  });

  testWidgets('barrier dismissal is silent, pending offer remains actionable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = offerFrom(1);
    final actions = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: state,
            online: true,
            viewingSeat: 0,
            observing: true,
            tradeReplyAllowed: true,
            onEvent: actions.add,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('incoming-trade-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('restore-bot-trade')), findsNothing);
    expect(actions, isEmpty);
    await tester.tap(find.text('Actions').first);
    await tester.pump();
    await tester.tap(find.text('Trade').first);
    await tester.pump();
    final decline = find.byKey(
      ValueKey('decline-offer-${state.offers.single.id}'),
    );
    expect(decline, findsOneWidget);
    await tester.ensureVisible(decline);
    await tester.tap(decline);
    expect(actions.single, isA<RespondTrade>());
  });
}
