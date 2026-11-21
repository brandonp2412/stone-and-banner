import 'package:flutter/material.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show display, tableWithSupplies;

void main() {
  testWidgets('ordinary road building has no redundant pop-up', (tester) async {
    final fresh = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 804);
    final settled = MatchEngine.apply(
      fresh,
      PlaceVillage(MatchEngine.legalVertices(fresh).first),
    );
    final expanded = MatchEngine.apply(
      settled,
      PlaceRoad(MatchEngine.legalEdges(settled).first),
    );
    Widget activity(MatchState state) =>
        MaterialApp(home: MatchActivity(state: state, viewerSeat: 0));
    await tester.pumpWidget(activity(settled));
    await tester.pumpWidget(activity(expanded));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('match-activity-notice')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mobile trade uses almost all space above the resource row', (
    tester,
  ) async {
    const size = Size(844, 390);
    await display(tester, size, tableWithSupplies());
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trade'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.text('Bank trade'));
    await tester.pumpAndSettle();

    final rect = tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    expect(rect.top, lessThanOrEqualTo(12));
    expect(rect.bottom, lessThan(size.height - 38));
    expect(rect.height, greaterThan(size.height - 90));
    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Close trade'), findsOneWidget);
    expect(find.byKey(const ValueKey('robber-hand-capacity')), findsNothing);
    expect(find.byTooltip('wood: 3'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/mobile_trade_fullheight.png'),
    );
  });

  testWidgets('profile navigation closes compact modal', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var rulesOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: tableWithSupplies(),
            onEvent: (_) {},
            onRules: () => rulesOpened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(rulesOpened, isTrue);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
