import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/strategy_hand.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [
    const Size(360, 780),
    const Size(780, 360),
    const Size(1280, 720),
  ]) {
    testWidgets('cards tab tracks own hand at $size', (tester) async {
      SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = tableWithSupplies();
      MatchState state(int count) {
        final players = base.players.toList();
        players[0] = players[0].copyWith(
          cards: List.generate(
            count,
            (i) => HeldCard(StrategyDeck.commerce, i),
          ),
        );
        players[1] = players[1].copyWith(
          cards: [const HeldCard(StrategyDeck.commerce, 0)],
        );
        return base.copyWith(players: players, active: 1);
      }

      Widget app(int count) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'NotoSans',
        ),
        home: MatchView(
          state: state(count),
          visibleSeat: 0,
          observing: true,
          onEvent: (_) {},
        ),
      );
      await tester.runAsync(loadTabletopArt);
      await tester.pumpWidget(app(0));
      await tester.pumpAndSettle();
      if (size.width < 900) {
        await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
        await tester.pumpAndSettle();
      }
      final cards = find.byTooltip('Cards');
      final badge = find.byKey(const ValueKey('cards-count-badge'));
      final build = find.byTooltip('Build');
      final initialWidth = tester.getSize(build).width;
      expect(cards, findsNothing);
      expect(badge, findsNothing);
      await tester.pumpWidget(app(1));
      await tester.pump(const Duration(milliseconds: 120));
      final midWidth = tester.getSize(build).width;
      expect(midWidth, lessThan(initialWidth));
      await tester.pumpAndSettle();
      expect(cards, findsOneWidget);
      expect(tester.getSize(build).width, lessThan(midWidth));
      expect(tester.widget<Text>(badge).data, '1');
      await tester.pumpWidget(app(3));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(badge).data, '3');
      await tester.tap(cards);
      await tester.pumpAndSettle();
      expect(find.byType(StrategyHand), findsOneWidget);
      if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/cards_tab_review_${size.width.toInt()}.png',
          ),
        );
      }
      await tester.pumpWidget(app(1));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(badge).data, '1');
      await tester.pumpWidget(app(0));
      await tester.pumpAndSettle();
      expect(cards, findsNothing);
      expect(badge, findsNothing);
      expect(find.byType(StrategyHand), findsNothing);
      expect(tester.getSize(build).width, closeTo(initialWidth, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
