import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> scrollToAction(WidgetTester tester, String label) async {
  final list = find.byKey(const ValueKey('mobile-action-hub'));
  final category = switch (label) {
    'Player trade' || 'Bank trade' => 'Trade',
    'Your realm' || 'Town Developments' => 'Realm',
    'Cards' || 'Strategy cards' => 'Cards',
    _ => 'Build',
  };
  final tab = find.text(category);
  if (tab.evaluate().isNotEmpty) {
    await tester.tap(tab.first);
    await tester.pumpAndSettle();
    if (find.byTooltip('Close trade').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Close trade'));
      await tester.pumpAndSettle();
    }
  }
  if (label == 'Cards') return;
  final controller = tester.widget<ListView>(list).controller!;
  controller.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    find.text(label),
    100,
    scrollable: find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}
