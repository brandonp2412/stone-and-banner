import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import '../test/action_helpers.dart';
import '../test/landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('mobile trade screen snapshot', (tester) async {
    final fonts = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(loadResourceIcons);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'NotoSans',
        ),
        home: Scaffold(
          body: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Player trade');
    await expectLater(
      find.byType(MatchView),
      matchesGoldenFile('visual_snapshots/trade_mobile.png'),
    );
  });

  testWidgets('offer composer snapshot', (tester) async {
    final fonts = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(loadResourceIcons);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'NotoSans',
        ),
        home: Scaffold(
          body: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Player trade');
    await tester.tap(find.text('Player trade'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Dialog),
      matchesGoldenFile('visual_snapshots/trade_composer.png'),
    );
  });

  testWidgets('cheeky theft and board burst snapshot', (tester) async {
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
    final before = tableWithSupplies().copyWith(active: 1);
    final after = before.copyWith(
      events: [...before.events, const MoveBandit(0, victim: 0)],
    );
    Widget app(MatchState s) => MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'NotoSans',
      ),
      home: Scaffold(
        body: MatchView(
          state: s,
          onEvent: (_) {},
          observing: true,
          visibleSeat: 0,
          computerSeats: const {1, 2, 3},
        ),
      ),
    );
    await tester.runAsync(loadResourceIcons);
    await tester.pumpWidget(app(before));
    await tester.runAsync(loadResourceIcons);
    await tester.pumpWidget(app(after));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MatchView),
      matchesGoldenFile('visual_snapshots/cheeky_theft.png'),
    );
  });
}
