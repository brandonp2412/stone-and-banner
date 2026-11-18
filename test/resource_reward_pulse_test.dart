import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/resource_harvest.dart';

void main() {
  testWidgets('tile pulses on gains and settles; spending does not pulse', (
    tester,
  ) async {
    Future<void> show(
      int count, {
      int seat = 0,
      bool reduced = false,
      bool deferred = false,
    }) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: ResourceRewardPulse(
            count: count,
            deferAnimation: deferred,
            seat: seat,
            color: Colors.green,
            child: const SizedBox(width: 50, height: 50),
          ),
        ),
      ),
    );
    double scale() => tester
        .widgetList<Transform>(find.byType(Transform))
        .last
        .transform
        .entry(0, 0);

    await show(2);
    expect(scale(), 1);
    await show(4);
    await tester.pump(const Duration(milliseconds: 180));
    expect(scale(), greaterThan(1));
    await tester.pumpAndSettle();
    expect(scale(), 1);
    await show(5, deferred: true);
    await tester.pump(const Duration(milliseconds: 600));
    expect(scale(), 1);
    await show(5);
    await tester.pump(const Duration(milliseconds: 180));
    expect(scale(), greaterThan(1));
    await tester.pumpAndSettle();
    await show(3);
    await tester.pump(const Duration(milliseconds: 180));
    expect(scale(), 1);
    await show(8, seat: 1);
    await tester.pump(const Duration(milliseconds: 180));
    expect(scale(), 1);
    await show(10, seat: 1, reduced: true);
    await tester.pump(const Duration(milliseconds: 180));
    expect(scale(), 1);
  });
}
