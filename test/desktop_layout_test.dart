import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  testWidgets('desktop fills the window and remains usable after resize', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('stone-home-page'))),
      const Size(1920, 1032),
    );
    expect(find.text('WELCOME TO THE TABLE'), findsOneWidget);
    for (final label in [
      'New local match',
      'Learn the rules',
      'LAN multiplayer',
      'Import replay',
    ]) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('stone-setup-page'))).width,
      1100,
    );
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm ready"));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('realm-map'))).width,
      greaterThan(1400),
    );
    expect(find.text('Build').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
