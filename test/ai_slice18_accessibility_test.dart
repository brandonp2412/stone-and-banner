import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  for (final variant in <(Size, double, Brightness)>[
    (const Size(320, 640), 1.6, Brightness.light),
    (const Size(390, 844), 2.0, Brightness.dark),
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

      await tester.tap(find.text('New local match'));
      await tester.pumpAndSettle();
      expect(find.text('Match setup'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Setup layout overflow');

      await tester.ensureVisible(find.text('Vs AI'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vs AI'));
      await tester.pumpAndSettle();
      expect(find.text('Computer opponents'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'AI options overflow');

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.menu_book_outlined),
        ),
      );
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
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.text('The founding rules'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('New local match'), findsOneWidget);
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
}
