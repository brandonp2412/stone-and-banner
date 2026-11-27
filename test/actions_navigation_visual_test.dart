import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('mobile actions expose one category at a time', (tester) async {
    await tester.runAsync(loadResourceIcons);
    await (FontLoader(
      'NotoSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'NotoSans',
        ),
        home: Scaffold(
          body: MatchView(
            state: tableWithSupplies(withCards: true),
            onEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/simple_roads.png'),
    );
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    expect(find.text('Road'), findsOneWidget);
    expect(find.text('Player trade'), findsNothing);
    expect(find.text('Guards & Defense'), findsNothing);
    expect(find.text('Fortify'), findsOneWidget);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/actions_gameplay.png'),
    );
    expect(find.text('Fortify'), findsOneWidget);
    await tester.tap(find.text('Trade'));
    await tester.pumpAndSettle();
    expect(find.text('Bank exchange'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/mobile_trade_tab.png'),
    );
    expect(find.text('Road'), findsNothing);
    expect(find.text('Player trade'), findsOneWidget);
    await tester.tap(find.text('Bank trade'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byTooltip('Close trade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.text('Player trade'), findsNothing);
    await tester.tap(find.text('Realm'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Your realm'),
      100,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('mobile-action-hub')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Your realm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Trade tab opens inline actions without a modal', (
    tester,
  ) async {
    await tester.runAsync(loadResourceIcons);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trade'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Player trade'), findsOneWidget);
    expect(find.text('Bank trade'), findsOneWidget);
    await tester.ensureVisible(find.text('Bank trade'));
    await tester.tap(find.text('Bank trade'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resource tray opens one trade modal while inventory remains visible',
    (tester) async {
      await tester.runAsync(loadResourceIcons);
      await (FontLoader(
        'NotoSans',
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(loadTabletopArt);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
          home: Scaffold(
            body: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ResourceIcon).first);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Player'), findsWidgets);
      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('Bank exchange'), findsOneWidget);
      expect(find.byType(ResourceIcon), findsWidgets);
      await tester.tap(find.text('Player').first);
      await tester.pumpAndSettle();
      expect(find.text('Standing offer'), findsOneWidget);
      await tester.tap(find.text('Bank'));
      await tester.pumpAndSettle();
      expect(find.text('Bank exchange'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
