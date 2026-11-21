import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/ui/compact_layout.dart';

void main() {
  for (final size in [const Size(780, 360), const Size(640, 320)]) {
    testWidgets('landscape screens preserve visible controls at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Gameplay hints'), findsOneWidget);
      expect(find.text('Computer action delay'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Learn the rules'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Learn the rules'));
      await tester.pumpAndSettle();
      expect(find.text('The essentials'), findsOneWidget);
      expect(find.text('Advanced play'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back to Home').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('New local match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New local match'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(3));
      final playButton = find.text('Start match');
      expect(playButton, findsOneWidget);
      final thirdField = tester.getRect(find.byType(TextField).last);
      final playRect = tester.getRect(playButton);
      expect(thirdField.bottom, lessThanOrEqualTo(playRect.top));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long alert content scrolls without hiding confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => CompactAlertDialog(
                  title: const Text('Pick resources'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 12; i++) Text('Resource $i'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget);
    final rect = tester.getRect(find.text('Confirm'));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });
}
