import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/trade_market.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );

  for (final size in [const Size(844, 390), const Size(1440, 900)]) {
    testWidgets('off-turn browsing works at $size, actions stay blocked', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = tableWithSupplies().copyWith(active: 1);
      final events = <MatchEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'NotoSans', brightness: Brightness.dark),
          home: Scaffold(
            body: MatchView(
              state: state,
              online: true,
              viewingSeat: 0,
              observing: true,
              onEvent: events.add,
            ),
          ),
        ),
      );
      await tester.pump();
      final mobile = size.width < 900;
      if (mobile) {
        await tester.tap(find.text('Actions').first);
        await tester.pump();
      }

      await tester.tap(find.text('Trade').first);
      await tester.pump();
      expect(find.byType(TradeMarket), findsOneWidget);
      expect(find.textContaining('Waiting for Ben'), findsWidgets);
      final create = find.byKey(const ValueKey('create-player-offer'));
      if (create.evaluate().isNotEmpty) {
        expect(tester.widget<FilledButton>(create).onPressed, isNull);
      }

      await tester.tap(find.text('Cards').first);
      await tester.pump();
      expect(find.textContaining('Strategy hand'), findsOneWidget);
      // This navigation button is within the panel previously blocked by
      // AbsorbPointer, and must still work when it isn't your turn.
      if (mobile) {
        await tester.tap(find.text('Develop').first);
        await tester.pump();
        expect(find.text('Your realm'), findsOneWidget);
      } else {
        await tester.tap(find.text('Realm').first);
        await tester.pump();
      }
      expect(find.text('Town Developments'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick-innovation-development')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('quick-innovation-development')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Build').first);
      await tester.pump();
      final road = find.widgetWithText(OutlinedButton, 'Road');
      expect(road, findsOneWidget);
      expect(tester.widget<OutlinedButton>(road).onPressed, isNull);
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
