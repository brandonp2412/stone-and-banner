import 'action_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

Future<void> showMobileMatch(
  WidgetTester tester,
  Size size, {
  double scale = 1,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(
        body: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectCategory(WidgetTester tester, String category) async {
  await scrollToAction(
    tester,
    {
      'Build': 'Road',
      'Trade': 'Player trade',
      'Cards': 'Cards',
      'Realm': 'Your realm',
    }[category]!,
  );
}

Future<void> openCategory(WidgetTester tester, String category) async {
  await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
  await tester.pumpAndSettle();
  await selectCategory(tester, category);
}

void main() {
  for (final size in [
    const Size(360, 740),
    const Size(393, 852),
    const Size(640, 320),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('mobile actions fill the screen at $size / $scale', (
        tester,
      ) async {
        await showMobileMatch(tester, size, scale: scale);
        final map = tester.getRect(find.byKey(const ValueKey('realm-map')));
        expect(map.width, closeTo(size.width, .1));
        if (size.width > size.height) {
          // The map must dominate landscape phones rather than losing space
          // to permanent side panels, instruction strips or action bars.
          expect(
            map.height / size.height,
            greaterThan(scale > 1.2 ? .60 : .70),
          );
          final actions = tester.getRect(
            find.byKey(const ValueKey('mobile-open-actions')),
          );
          final turn = tester.getRect(find.text('End turn'));
          expect(actions.right, lessThan(size.width * .28));
          expect(turn.left, greaterThan(size.width * .72));
          expect(actions.bottom, lessThanOrEqualTo(map.bottom));
          expect(turn.bottom, lessThanOrEqualTo(map.bottom));
        }
        expect(find.text('Build'), findsNothing);
        expect(find.text('End turn').hitTestable(), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('realm-map')), findsNothing);
        expect(find.byKey(const ValueKey('mobile-action-hub')), findsOneWidget);
        expect(find.text('Build').hitTestable(), findsOneWidget);
        await selectCategory(tester, 'Trade');
        await tester.pumpAndSettle();
        expect(find.text('Bank trade').hitTestable(), findsOneWidget);
        expect(find.text('Player trade').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Back to map'), findsOneWidget);

        expect(find.byKey(const ValueKey('mobile-action-hub')), findsOneWidget);
        await tester.tap(find.byTooltip('Back to map'));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(const ValueKey('realm-map'))), map);
        expect(find.text('End turn').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('choosing a build piece returns immediately to the map', (
    tester,
  ) async {
    await showMobileMatch(tester, const Size(393, 852));
    await openCategory(tester, 'Build');
    expect(find.text('Road').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Road'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
    expect(find.text('Build a road'), findsOneWidget);
    expect(find.byTooltip('Cancel selection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions return directly to map with system back', (
    tester,
  ) async {
    await showMobileMatch(tester, const Size(393, 852));
    await openCategory(tester, 'Realm');
    expect(find.byTooltip('Back to map'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('build details fill available space without turn footer', (
    tester,
  ) async {
    await showMobileMatch(tester, const Size(640, 320));
    await openCategory(tester, 'Build');
    final list = find.byType(ListView);
    expect(list, findsOneWidget);
    expect(find.text('End turn'), findsNothing);
    final listRect = tester.getRect(list);
    expect(listRect.bottom, closeTo(320, 1));
    expect(find.byTooltip('wood: 3'), findsNothing);
    await tester.drag(list, const Offset(0, -230));
    await tester.pumpAndSettle();
    expect(tester.widget<ListView>(list).controller!.offset, greaterThan(0));
    await tester.tap(find.byTooltip('Back to map'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
    expect(find.text('End turn').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
