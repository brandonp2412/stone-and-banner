import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('home, playable board and rules golden snapshots', (
    tester,
  ) async {
    await tester.runAsync(loadResourceIcons);
    final fonts = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(StoneBannerApp(worldSeedFactory: () => 20261027));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/home.png'),
    );
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/setup.png'),
    );
    await tester.ensureVisible(find.text('Start match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm ready"));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/board.png'),
    );
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/actions.png'),
    );
    await tester.scrollUntilVisible(
      find.text('Rules'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('mobile-action-hub')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules').last);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/rules.png'),
    );
  });
}
