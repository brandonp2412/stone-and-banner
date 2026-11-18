import 'action_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/trade_feedback.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  MatchState offered() => MatchEngine.apply(
    tableWithSupplies(),
    const ProposeTrade(1, Resource.wood, 1, Resource.brick, 1),
  );

  test(
    'decline reports recorded recipient and refunded terms across turns',
    () {
      final pending = offered();
      expect(latestTradeFeedback(pending), isNull);
      final answered = MatchEngine.apply(
        pending.copyWith(active: 1),
        RespondTrade(1, false, offerId: pending.offers.single.id),
      );
      expect(answered.offers, isEmpty);
      expect(
        latestTradeFeedback(answered),
        'Ben declined the trade: 1 wood for 1 brick. Reserved goods returned.',
      );
      expect(
        latestTradeFeedback(answered.copyWith(active: 0)),
        latestTradeFeedback(answered),
      );
    },
  );

  test('acceptance reports the completed exchange', () {
    final pending = offered();
    final recipient = pending.players[1];
    final bank = Map<Resource, int>.of(pending.bank);
    bank[Resource.brick] = bank[Resource.brick]! - 1;
    final players = pending.players.toList();
    players[1] = recipient.copyWith(
      stores: {
        ...recipient.stores,
        Resource.brick: (recipient.stores[Resource.brick] ?? 0) + 1,
      },
    );
    final answered = MatchEngine.apply(
      pending.copyWith(active: 1, players: players, bank: bank),
      RespondTrade(1, true, offerId: pending.offers.single.id),
    );
    expect(
      latestTradeFeedback(answered),
      'Ben accepted the trade: 1 wood for 1 brick.',
    );
  });

  test('withdrawal is not reported as a rejection', () {
    final pending = offered();
    final withdrawn = MatchEngine.apply(
      pending,
      WithdrawTrade(pending.offers.single.id),
    );
    expect(latestTradeFeedback(withdrawn), isNull);
  });

  testWidgets('answer notifies immediately and persists in Trade panel', (
    tester,
  ) async {
    final pending = offered();
    final answered = MatchEngine.apply(
      pending.copyWith(active: 1),
      RespondTrade(1, false, offerId: pending.offers.single.id),
    );
    Widget app(MatchState state) => MaterialApp(
      home: Scaffold(
        body: MatchView(state: state, onEvent: (_) {}),
      ),
    );
    await tester.pumpWidget(app(pending));
    await tester.pumpWidget(app(answered));
    await tester.pump();
    expect(find.byKey(const ValueKey('match-activity-notice')), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Player trade');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trade-result')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
