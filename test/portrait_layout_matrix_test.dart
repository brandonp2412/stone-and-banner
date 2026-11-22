import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart' show StoneBannerApp;
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

Future<void> setupSize(WidgetTester tester, Size size, double scale) async {
  SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void checkVisible(WidgetTester tester, Finder finder, Size size) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(-1));
  expect(rect.bottom, lessThanOrEqualTo(size.height + 1));
  expect(rect.left, greaterThanOrEqualTo(-1));
  expect(rect.right, lessThanOrEqualTo(size.width + 1));
}

void main() {
  testWidgets('portrait setup stays usable with the keyboard visible', (
    tester,
  ) async {
    const size = Size(393, 852);
    await setupSize(tester, size, 1.5);
    await tester.pumpWidget(const StoneBannerApp(randomizeTurnOrder: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 310);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    final start = tester.getRect(find.text('Start match'));
    expect(start.bottom, lessThan(852 - 310));
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 568),
    const Size(360, 740),
    const Size(393, 852),
  ]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('portrait match and trades usable at $size scale $scale', (
        tester,
      ) async {
        await setupSize(tester, size, scale);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
            home: Scaffold(
              body: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        checkVisible(
          tester,
          find.byKey(const ValueKey('mobile-open-actions')),
          size,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('mobile-action-hub')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final tradeTab = find.text('Trade').last;
        await tester.ensureVisible(tradeTab);
        await tester.tap(tradeTab);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('create-player-offer')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('create-player-offer')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 360));
        checkVisible(tester, find.text('Send offer'), size);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Bank').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 360));
        checkVisible(tester, find.text('Exchange'), size);
        expect(tester.takeException(), isNull);
      });

      testWidgets('portrait home and setup usable at $size scale $scale', (
        tester,
      ) async {
        await setupSize(tester, size, scale);
        await tester.pumpWidget(
          const StoneBannerApp(randomizeTurnOrder: false),
        );
        await tester.pumpAndSettle();
        final newMatch = find.text('New local match');
        await tester.ensureVisible(newMatch);
        await tester.tap(newMatch);
        await tester.pumpAndSettle();
        checkVisible(tester, find.text('Start match'), size);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
