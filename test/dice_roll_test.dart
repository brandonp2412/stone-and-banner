import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/dice_roll.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('roll button throws dice over the board and clears the effect', (
    tester,
  ) async {
    var state = tableWithSupplies().copyWith(phase: MatchPhase.roll);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) {
              return MatchView(
                state: state,
                onEvent: (event) => refresh(() {
                  state = MatchEngine.apply(state, event);
                }),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DiceRoll), findsNothing);
    final expected = MatchEngine.expectedDice(state);
    await tester.tap(find.text('Roll').first);
    await tester.pump();
    expect(find.byType(DiceRoll), findsOneWidget);
    expect(find.text('Rolling…'), findsOneWidget);
    final board = tester.getRect(find.byKey(const ValueKey('realm-map')));
    expect(board.contains(tester.getCenter(find.byType(DiceRoll))), isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.text(
        '${expected.$1} + ${expected.$2} = ${expected.$1 + expected.$2}',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DiceRoll), findsNothing);
    expect(find.byType(MatchView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('roll reveals supplied result then closes automatically', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const DiceRoll(first: 2, second: 5),
              ),
              child: const Text('Roll'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Roll'));
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Rolling…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('2 + 5 = 7'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(DiceRoll), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
