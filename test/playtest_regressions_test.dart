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
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('Player trade'));
      await tester.pumpAndSettle();
      final giveWood = find.byKey(const ValueKey('trade-give-wood'));
      final getWheat = find.byKey(const ValueKey('trade-get-wheat'));
      expect(tester.widget<InkWell>(giveWood).onTap, isNotNull);
      expect(tester.widget<InkWell>(getWheat).onTap, isNotNull);
      await tester.tap(giveWood);
      await tester.tap(getWheat);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove one wood from offer'), findsOneWidget);
      expect(find.byTooltip('Remove one wheat from request'), findsOneWidget);
      expect(find.textContaining('escrow', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('board target picker is absent', (tester) async {
    final state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 20261118);
    await display(tester, const Size(844, 390), state);
    expect(find.byTooltip('Choose target'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
