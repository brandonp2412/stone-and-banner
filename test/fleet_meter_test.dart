import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/invasion_meter.dart';

void main() {
  testWidgets('fleet countdown stays readable in the narrow board HUD', (
    tester,
  ) async {
    final state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 100);
    for (var pressure = 0; pressure <= 3; pressure++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 108,
                child: InvasionMeter(
                  state: state.copyWith(
                    reaverPressure: pressure,
                    phase: pressure == 3
                        ? MatchPhase.invasion
                        : MatchPhase.roll,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.text(switch (pressure) {
          0 => 'Invasion in 3 rounds',
          1 => 'Invasion in 2 rounds',
          2 => 'Invasion in 1 round',
          _ => 'Invasion now',
        }),
        findsOneWidget,
      );
      expect(find.text('Defence 0 / 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
