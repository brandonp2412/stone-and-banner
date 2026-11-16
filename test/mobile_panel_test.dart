import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  for (final scale in [1.0, 1.6]) {
    for (final size in [const Size(640, 320), const Size(844, 390)]) {
      testWidgets(
        'mobile panel scrolls independently and expands at $size / $scale',
        (tester) async {
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
          final map = tester.getRect(find.byType(InteractiveViewer));
          final turn = tester.getRect(find.text('End turn'));
          final list = find.byType(ListView);
          final controller = tester.widget<ListView>(list).controller!;
          await tester.drag(list, const Offset(0, -220));
          await tester.pumpAndSettle();
          expect(controller.offset, greaterThan(0));
          final offset = controller.offset;
          expect(tester.getRect(find.byType(InteractiveViewer)), map);
          expect(tester.getRect(find.text('End turn')), turn);
          await tester.tap(find.text('Trade'));
          await tester.pumpAndSettle();
          expect(tester.widget<ListView>(list).controller!.offset, 0);
          expect(find.text('Bank trade').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Build'));
          await tester.pumpAndSettle();
          expect(controller.offset, closeTo(offset, .1));
          await tester.tap(find.byTooltip('Expand action panel'));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byType(InteractiveViewer)).width,
            lessThan(map.width),
          );
          expect(find.text('End turn').hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip('Narrow action panel'));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(InteractiveViewer)), map);
          for (final tab in ['Cards', 'Realm', 'Build']) {
            await tester.tap(find.text(tab));
            await tester.pumpAndSettle();
            expect(find.text('End turn').hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
