import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/replay_codes.dart';

void main() {
  for (final variant in <(Size, double, Brightness)>[
    (const Size(640, 320), 1.6, Brightness.light),
    (const Size(844, 390), 2.0, Brightness.dark),
    (const Size(1024, 768), 1.0, Brightness.light),
  ]) {
    testWidgets('Home, setup and Rules fit ${variant.$1} at ${variant.$2}x', (
      tester,
    ) async {
      tester.view.physicalSize = variant.$1;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = variant.$2;
      tester.platformDispatcher.platformBrightnessTestValue = variant.$3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      expect(find.text('New local match'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Home layout overflow');

      await tester.ensureVisible(find.text('New local match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New local match'));
      await tester.pumpAndSettle();
      expect(find.text('Match setup'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Setup layout overflow');

      await tester.scrollUntilVisible(
        find.text('Vs bots'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vs bots'));
      await tester.pumpAndSettle();
      expect(find.text('Computer opponents'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'AI options overflow');

      await tester.tap(find.byTooltip('Back to Home').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Learn the rules'));
      await tester.tap(find.text('Learn the rules'));
      await tester.pumpAndSettle();
      expect(find.text('The founding rules'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Rules overflow');
    });
  }

  testWidgets('Home keyboard traversal reaches an actionable control', (
    tester,
  ) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('Escape returns from Rules and setup without losing Home', (
    tester,
  ) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn the rules'));
    await tester.pumpAndSettle();
    expect(find.text('The founding rules'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('New local match'), findsOneWidget);
    await tester.ensureVisible(find.text('New local match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    expect(find.text('Match setup'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('New local match'), findsOneWidget);
  });

  testWidgets('Escape dismisses replay import without changing pages', (
    tester,
  ) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import replay'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('New local match'), findsOneWidget);
  });
  testWidgets('landscape replay input remains usable above the keyboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import replay'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TextField)).height, greaterThan(40));
    final code = ReplayCodes.compact(
      MatchEngine.exportReplay(
        MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 804),
      ),
    );
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('Load'));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
