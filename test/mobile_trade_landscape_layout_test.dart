import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('mobile landscape Trade tray and composer stay usable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trade').last);
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('resource-tile-wood'));
    expect(tile, findsOneWidget);
    expect(tester.getBottomLeft(tile).dy, lessThanOrEqualTo(390));
    expect(find.byKey(const ValueKey('create-player-offer')), findsOneWidget);
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('create-player-offer')))
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('mobile-minimize-trade')), findsOneWidget);
    expect(find.text('Send offer'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('Send offer')).dy, lessThan(390));
    await tester.tap(find.text('Bank').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('bank-bundles-plus')), findsOneWidget);
    expect(find.text('Exchange'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('Exchange')).dy, lessThan(390));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('landscape map raid HUD displays just its compact title', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    final hud = find.byKey(const ValueKey('mobile-raid-defense-hud'));
    expect(hud, findsOneWidget);
    expect(find.text('Raid Defense'), findsOneWidget);
    expect(tester.getSize(hud).height, lessThan(35));
    expect(tester.getSize(hud).width, lessThanOrEqualTo(170));
    expect(find.textContaining('ROUND'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
