import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart' show StoneBannerApp;
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

Future<void> portraitSetup(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
  await tester.runAsync(loadResourceIcons);
  await (FontLoader(
    'NotoSans',
  )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
  await (FontLoader(
    'NotoSans',
  )..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> renderMatch(WidgetTester tester, {MatchState? state}) async {
  await tester.runAsync(loadTabletopArt);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'NotoSans',
      ),
      home: Scaffold(
        body: MatchView(state: state ?? tableWithSupplies(), onEvent: (_) {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> golden(WidgetTester tester, String filename) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/portrait_$filename.png'),
  );
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('home and setup portrait snapshots', (tester) async {
    await portraitSetup(tester);
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(const StoneBannerApp(randomizeTurnOrder: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stone-home-page')), findsOneWidget);
    await golden(tester, 'home');
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stone-setup-page')), findsOneWidget);
    expect(find.text('Start match'), findsOneWidget);
    await golden(tester, 'setup');
    await tester.tap(find.text('Vs bots'));
    await tester.pumpAndSettle();
    await golden(tester, 'setup_ai');
  });

  testWidgets('board and action categories portrait snapshots', (tester) async {
    await portraitSetup(tester);
    await renderMatch(tester);
    await golden(tester, 'board');
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    await golden(tester, 'actions');
    await tester.tap(find.text('Trade').last);
    await tester.pumpAndSettle();
    await golden(tester, 'trade_tab');
    await tester.tap(find.text('Cards').last);
    await tester.pumpAndSettle();
    await golden(tester, 'cards');
    await tester.tap(find.text('Realm').last);
    await tester.pumpAndSettle();
    await golden(tester, 'realm');
  });

  testWidgets('trade composers portrait snapshots', (tester) async {
    await portraitSetup(tester);
    await renderMatch(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trade').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-player-offer')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('create-player-offer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 380));
    expect(find.text('Send offer'), findsOneWidget);
    await golden(tester, 'player_trade');
    await tester.tap(find.text('Bank').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 380));
    expect(find.text('Exchange'), findsOneWidget);
    await golden(tester, 'bank_trade');
  });

  testWidgets('invasion response portrait snapshot', (tester) async {
    await portraitSetup(tester);
    final base = tableWithSupplies();
    final fortified = base.copyWith(
      phase: MatchPhase.invasion,
      sites: {...base.sites, 1: const Site(0, Structure.town)},
      tactical: TacticalWindow(100, TacticalKind.invasion, 0, [0, 1, 2]),
    );
    await renderMatch(tester, state: fortified);
    expect(find.text('Invasion emergency aid'), findsOneWidget);
    await golden(tester, 'invasion');
  });
}
