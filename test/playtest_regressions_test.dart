import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';

import 'landscape_tabletop_test.dart' show display, tableWithSupplies;

void main() {
  testWidgets('affordable village explains why no site is legal', (
    tester,
  ) async {
    final state = tableWithSupplies().copyWith(roads: <int, int>{});
    expect(MatchEngine.legalVertices(state), isEmpty);
    await display(tester, const Size(844, 390), state);
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Extend a road first'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'player trade displays quantity controls without escrow language',
    (tester) async {
      await display(tester, const Size(844, 390), tableWithSupplies());
      await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trade'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('Player').first);
      await tester.pumpAndSettle();
      expect(find.text('Quantity'), findsNWidgets(2));
      expect(find.byTooltip('Increase quantity'), findsNWidgets(2));
      expect(find.textContaining('escrow', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('landscape board target picker uses most of screen height', (
    tester,
  ) async {
    final state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 20261118);
    await display(tester, const Size(844, 390), state);
    await tester.tap(find.byTooltip('Choose target'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(tester.getSize(sheet).height, greaterThan(300));
    expect(find.textContaining('Junction'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
