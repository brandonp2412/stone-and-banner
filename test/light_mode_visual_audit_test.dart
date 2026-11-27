import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart' show StoneBannerApp;
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'strategy_cards_widget_test.dart' show withCard;

import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/trade_market.dart';

import 'portrait_finale_test.dart' show finaleFixture;

import 'package:stone_and_banner/ui/match_end_modal.dart';
import 'package:stone_and_banner/ui/lan_room_page.dart';
import 'package:stone_and_banner/ui/p2p_room_page.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

Future<void> auditSetup(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({
    'gameplay_hints_enabled': false,
    'themeMode': 'light',
  });
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
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> renderMatch(WidgetTester tester, {MatchState? state}) async {
  await tester.runAsync(loadTabletopArt);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff806334)),
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
  if (filename == 'home') {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/art/stone_banner_crest.jpg'),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await tester.pump();
  }

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(
      'goldens/light_${tester.view.physicalSize.width.toInt()}_$filename.png',
    ),
  );
  expect(tester.takeException(), isNull);
}

void main() {
  for (final size in [
    const Size(393, 852),
    const Size(844, 390),
    const Size(1440, 900),
  ]) {
    group('light mode at $size', () {
      testWidgets('home and setup snapshots', (tester) async {
        await auditSetup(tester, size);
        await tester.runAsync(loadTabletopArt);
        await tester.pumpWidget(
          const StoneBannerApp(randomizeTurnOrder: false),
        );
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

      testWidgets('board and action categories snapshots', (tester) async {
        await auditSetup(tester, size);
        await renderMatch(tester);
        await golden(tester, 'board');
        if (size.width < 900) {
          await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
        }
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

      testWidgets('trade composer snapshots', (tester) async {
        await auditSetup(tester, size);
        await renderMatch(tester);
        if (size.width < 900) {
          await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Trade').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('create-player-offer')),
          findsOneWidget,
        );
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

      testWidgets('rules, settings, history and multiplayer', (tester) async {
        await auditSetup(tester, size);
        await tester.runAsync(loadTabletopArt);
        await tester.pumpWidget(
          const StoneBannerApp(randomizeTurnOrder: false),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Learn the rules'));
        await tester.pumpAndSettle();
        await golden(tester, 'rules');
        await tester.tap(find.byTooltip('Back to Home'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await golden(tester, 'settings');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Match history'));
        await tester.pumpAndSettle();
        await golden(tester, 'history');
        for (final (name, page) in <(String, Widget)>[
          ('lan', const LanRoomPage()),
          ('p2p', const P2pRoomPage()),
        ]) {
          await tester.runAsync(loadTabletopArt);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'NotoSans',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff806334),
                ),
              ),
              home: page,
            ),
          );
          // Let socket discovery finish before disposing the LAN page.
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 500));
          }
          await tester.pumpAndSettle();
          await golden(tester, name);
        }
      });
      for (final victory in [true, false]) {
        testWidgets('finale victory=$victory', (tester) async {
          await auditSetup(tester, size);
          await tester.runAsync(loadTabletopArt);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'NotoSans',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff806334),
                ),
              ),
              home: Scaffold(
                body: MatchEndModal(
                  state: finaleFixture(),
                  winner: 0,
                  victory: victory,
                  onReview: () {},
                  onHome: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 1100));
          await golden(tester, victory ? 'victory' : 'defeat');
        });
      }
      testWidgets('populated offers, card detail and resource picker', (
        tester,
      ) async {
        await auditSetup(tester, size);
        final pending = MatchEngine.apply(
          tableWithSupplies(),
          const ProposeTrade(1, Resource.wood, 1, Resource.brick, 1),
        );
        await tester.runAsync(loadTabletopArt);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'NotoSans',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff806334),
              ),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: TradeMarket(
                  state: pending,
                  viewerSeat: 1,
                  onBank: () {},
                  onOffer: () {},
                  onCounter: (_) {},
                  onEvent: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await golden(tester, 'incoming_trade');
        await renderMatch(tester, state: withCard('forecast'));
        if (size.width < 900) {
          await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cards').last);
        await tester.pumpAndSettle();
        await golden(tester, 'held_card');
        await tester.tap(find.byTooltip('Card details and discard'));
        await tester.pumpAndSettle();
        await golden(tester, 'card_detail');
        await tester.runAsync(loadTabletopArt);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.runAsync(loadTabletopArt);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'NotoSans',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff806334),
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showResourceIconPicker(context),
                  child: const Text('Icons'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Icons'));
        await tester.pumpAndSettle();
        await golden(tester, 'icon_picker');
      });
      testWidgets('invasion response snapshot', (tester) async {
        await auditSetup(tester, size);
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
    });
  }
}
