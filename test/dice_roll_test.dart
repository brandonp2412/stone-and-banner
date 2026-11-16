import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/dice_roll.dart';

void main() {
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
    expect(find.text('Rolling dice…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1250));
    expect(find.text('2 + 5 = 7'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(DiceRoll), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
