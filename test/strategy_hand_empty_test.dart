import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/strategy_hand.dart';

void main() {
  testWidgets('empty strategy hand explains development and opens Realm', (
    tester,
  ) async {
    final state = MatchEngine.newGame([
      'Ada',
      'Ben',
      'Cora',
    ], 804).copyWith(phase: MatchPhase.actions);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StrategyHand(
              state: state,
              onEvent: (_) {},
              onOpenRealm: () => opened = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('No strategy cards yet'), findsOneWidget);
    expect(
      find.text('Develop Town tracks to unlock card draws.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Develop'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
