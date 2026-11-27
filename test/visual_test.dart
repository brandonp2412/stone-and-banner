import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );
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
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(
      StoneBannerApp(
        worldSeedFactory: () => 20261027,
        randomizeTurnOrder: false,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/home.png'),
    );
    // Rules live on the home page; the action hub intentionally has no
    // duplicate Rules tab on compact landscape.
    await tester.tap(find.text('Learn the rules'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/rules.png'),
    );
    await tester.tap(find.byTooltip('Back to Home'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-action-hub')), findsOneWidget);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/actions.png'),
    );
  });
}
