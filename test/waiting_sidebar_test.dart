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
        expect(find.text('Player trade'), findsOneWidget);
        final trade = find.byKey(const ValueKey('create-player-offer'));
        expect(
          find.ancestor(
            of: trade,
            matching: find.byWidgetPredicate(
              (w) => w is AbsorbPointer && w.absorbing,
            ),
          ),
          findsWidgets,
        );
        await tester.tap(trade, warnIfMissed: false);
        await tester.pump();
        expect(events, isEmpty);
        expect(find.byType(Dialog), findsNothing);
        await tester.pumpWidget(view(false));
        await tester.pumpAndSettle();
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('create-player-offer')),
            matching: find.byWidgetPredicate(
              (w) => w is AbsorbPointer && w.absorbing,
            ),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
