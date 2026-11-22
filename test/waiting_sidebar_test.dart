import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'waiting keeps disabled actions on ${mobile ? "mobile" : "desktop"}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = mobile
            ? const Size(430, 900)
            : const Size(1440, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final events = <MatchEvent>[];
        Widget view(bool observing) => MaterialApp(
          home: Scaffold(
            body: MatchView(
              state: tableWithSupplies(),
              observing: observing,
              onEvent: events.add,
            ),
          ),
        );
        await tester.pumpWidget(view(true));
        if (mobile) {
          await tester.tap(find.text('Actions'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Build'), findsOneWidget);
        expect(find.text('Trade'), findsOneWidget);
        await tester.tap(find.text('Trade'));
        await tester.pumpAndSettle();
        expect(
          find.text('Player trade'),
          mobile ? findsNothing : findsOneWidget,
          reason: mobile
              ? 'Mobile tabs stay inert outside the player’s turn'
              : 'Desktop tabs stay navigable outside the player’s turn',
        );
        expect(events, isEmpty);
        await tester.pumpWidget(view(false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Trade'));
        await tester.pumpAndSettle();
        expect(find.text('Player trade'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('create-player-offer')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
