import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';
import 'package:stone_and_banner/ui/resource_label.dart';

void main() {
  testWidgets('compact resource labels retain full accessibility names', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    const label = '2 wheat · 3 ore · 1 sheep';
    Future<void> show(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const ResourceLabel(label, adaptive: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(150);
    expect(find.byType(ResourceIcon), findsNWidgets(3));
    expect(
      tester
          .widgetList<ResourceIcon>(find.byType(ResourceIcon))
          .map((icon) => icon.resource),
      [Resource.wheat, Resource.ore, Resource.wool],
    );
    expect(find.text('wheat'), findsNothing);
    expect(find.bySemanticsLabel(label), findsOneWidget);
    expect(tester.takeException(), isNull);
    await show(600);
    expect(find.text('wheat'), findsOneWidget);
    expect(find.text('ore'), findsOneWidget);
    expect(find.text('sheep'), findsOneWidget);
    expect(find.bySemanticsLabel(label), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
