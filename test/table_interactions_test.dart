import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/ui/match_activity.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('own player card opens settings and emotes reach the table', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = tableWithSupplies();
    var settings = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(
          state: state,
          onEvent: (_) {},
          onSettings: () async {
            settings++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(settings, 1);
    // Navigating from profile options now dismisses the bottom sheet.
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byTooltip('React'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👋'));
    await tester.pumpAndSettle();
    expect(find.text(state.players[0].id), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Fortify has a concise tooltip on long press', (tester) async {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    final fortify = find.text('Fortify');
    await tester.ensureVisible(fortify);
    await tester.longPress(fortify);
    await tester.pump();
    expect(find.textContaining('Fortify ·'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual emotes show without adding match events', (tester) async {
    final state = tableWithSupplies();
    Widget app(int serial) => MaterialApp(
      home: MatchActivity(
        state: state,
        viewerSeat: 0,
        emote: '👏',
        emoteSerial: serial,
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpWidget(app(1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('👏'), findsOneWidget);
    expect(find.text(state.players[0].id), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
