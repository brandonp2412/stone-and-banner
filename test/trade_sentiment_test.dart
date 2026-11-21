import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/trade_sentiment.dart';
import 'package:stone_and_banner/ui/match_activity.dart';

void main() {
  MatchState funded(int seed) {
    final s = MatchEngine.newGame(['Ada', 'Ben', 'Cora', 'Dee'], seed);
    return s.copyWith(
      active: 1,
      phase: MatchPhase.actions,
      players: [
        for (final p in s.players)
          p.copyWith(stores: {for (final good in Resource.values) good: 5}),
      ],
    );
  }

  // Vary the public board seed to exercise both outcomes without flaky RNG.
  MatchState declined(int seed, {bool accept = false}) {
    var s = funded(seed);
    s = MatchEngine.apply(
      s,
      const ProposeTrade(0, Resource.wood, 1, Resource.brick, 1),
    );
    return MatchEngine.apply(
      s,
      RespondTrade(0, accept, offerId: s.offers.single.id),
    );
  }

  test('declines sometimes cause persistent, recipient-specific anger', () {
    var angry = 0;
    for (var seed = 1; seed <= 100; seed++) {
      final s = declined(seed);
      final reacts = TradeSentiment.angryAtDecline(s, s.events.length - 1);
      expect(TradeSentiment.grievances(s, 1)[0] ?? 0, reacts ? 1 : 0);
      expect(TradeSentiment.grievances(s, 0), isEmpty);
      expect(TradeSentiment.grievances(s, 2), isEmpty);
      if (reacts) angry++;
      final accepted = declined(seed, accept: true);
      expect(TradeSentiment.grievances(accepted, 1), isEmpty);
    }
    expect(angry, inExclusiveRange(15, 50));
  });

  test(
    'anger reduces offer opportunities without blocking other recipients',
    () {
      final s = declined(1);
      var once = 0;
      var repeated = 0;
      for (var round = 1; round <= 100; round++) {
        final turn = s.copyWith(round: round);
        expect(TradeSentiment.willingToOffer(turn, 1, 2, 0), isTrue);
        if (TradeSentiment.willingToOffer(turn, 1, 0, 1)) once++;
        if (TradeSentiment.willingToOffer(turn, 1, 0, 2)) repeated++;
      }
      expect(once, inExclusiveRange(30, 70));
      expect(repeated, inExclusiveRange(10, 40));
      expect(repeated, lessThan(once));
    },
  );

  testWidgets('angry AI displays its reaction after a human decline', (
    tester,
  ) async {
    final after = Iterable.generate(
      100,
      (i) => declined(i + 1),
    ).firstWhere((s) => TradeSentiment.angryAtDecline(s, s.events.length - 1));
    var before = funded(after.board.seed);
    before = MatchEngine.apply(
      before,
      const ProposeTrade(0, Resource.wood, 1, Resource.brick, 1),
    );
    Widget app(MatchState state) => MaterialApp(
      home: Scaffold(
        body: MatchActivity(
          state: state,
          viewerSeat: 0,
          computerSeats: const {1},
        ),
      ),
    );
    await tester.pumpWidget(app(before));
    await tester.pumpWidget(app(after));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('😤'), findsOneWidget);
    expect(
      find.text('They’ll offer you fewer trades from now on.'),
      findsOneWidget,
    );
    // The same history used by the reaction removes offers on unwilling rounds.
    final blocked = Iterable.generate(
      100,
      (i) => after.copyWith(
        round: i + 1,
        events: [...after.events, for (var j = 0; j < 4; j++) const EndTurn()],
      ),
    ).firstWhere((s) => !TradeSentiment.willingToOffer(s, 1, 0, 1));
    final view = AiActionAdapter.observe(blocked, 1);
    expect(
      view.legalActions.whereType<ProposeTrade>().where((a) => a.target == 0),
      isEmpty,
    );
    expect(
      view.legalActions.whereType<ProposeTrade>().where((a) => a.target == 2),
      isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
