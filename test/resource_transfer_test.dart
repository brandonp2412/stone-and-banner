import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/resource_transfer.dart';

void main() {
  testWidgets('chips transfer goods, cap selection, and return goods', (
    tester,
  ) async {
    var selection = <Resource, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => ResourceTransfer(
              title: 'DISCARD',
              selected: selection,
              holdings: const {Resource.wood: 2, Resource.ore: 1},
              limit: 2,
              onChanged: (next) => update(() => selection = next),
            ),
          ),
        ),
      ),
    );
    final wood = find.byKey(const ValueKey('transfer-DISCARD-add-wood'));
    final ore = find.byKey(const ValueKey('transfer-DISCARD-add-ore'));
    await tester.tap(wood);
    await tester.pumpAndSettle();
    await tester.tap(ore);
    await tester.pumpAndSettle();
    expect(selection, {Resource.wood: 1, Resource.ore: 1});
    expect(tester.widget<ActionChip>(wood).onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey('transfer-DISCARD-remove-wood')),
    );
    await tester.pumpAndSettle();
    expect(selection, {Resource.ore: 1});
    expect(tester.widget<ActionChip>(wood).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
