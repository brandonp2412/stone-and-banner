import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  testWidgets('home, preview turns, rules and navigation work', (tester) async {
    await tester.pumpWidget(const StoneBannerApp());
    expect(find.text('Raise a town. Shape a realm.'), findsOneWidget);
    await tester.tap(find.text('Open board preview'));
    await tester.pumpAndSettle();
    expect(find.text('The frontier'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Turn: Player 1'), 180);
    expect(find.text('Turn: Player 1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Advance preview turn'), 120);
    await tester.tap(find.text('Advance preview turn'));
    await tester.pumpAndSettle();
    expect(find.text('Turn: Player 2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu_book_outlined).first);
    await tester.pumpAndSettle();
    expect(find.text('The founding rules'), findsOneWidget);
    expect(find.textContaining('Reach 15 Victory Points'), findsOneWidget);
  });
}
