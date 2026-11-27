import 'resource_label_finder.dart';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/emote_icon.dart';
import 'package:stone_and_banner/ui/match_activity.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

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
  setUp(() {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
  });

  testWidgets('desktop prefers village over guard at shared junction', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final original = tableWithSupplies();
    final junction = Iterable<int>.generate(original.topology.vertices.length)
        .firstWhere(
          (v) =>
              !original.sites.containsKey(v) &&
              !original.guards.containsKey(v) &&
              !original.topology
                  .neighbours(v)
                  .any(original.sites.containsKey) &&
              original.topology.vertices[v].edges.any(
                (e) => !original.roads.containsKey(e),
              ),
        );
    final newEdge = original.topology.vertices[junction].edges.firstWhere(
      (e) => !original.roads.containsKey(e),
    );
    final state = original.copyWith(
      roads: {...original.roads, newEdge: original.active},
    );
    expect(MatchEngine.legalVillage(state, junction), isTrue);
    expect(MatchEngine.legalRecruit(state, junction), isTrue);
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSans', brightness: Brightness.dark),
        home: MatchView(state: state, onEvent: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    final board = find.byKey(const ValueKey('realm-map'));
    final geometry = BoardGeometry(tester.getSize(board));
    final point =
        tester.getTopLeft(board) +
        geometry.vertex(state.topology.vertices[junction]);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(point);
    await tester.pump();
    expect(find.textContaining('Build a village'), findsOneWidget);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('Build village'),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Build Guard'),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
    await mouse.removePointer();
  });

  testWidgets('large desktop shows emotes as toasts below the player tiles', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final state = tableWithSupplies();
    Widget screen(int serial) => MaterialApp(
      theme: ThemeData(fontFamily: 'NotoSans', brightness: Brightness.dark),
      home: MatchView(
        state: state,
        online: true,
        viewingSeat: 0,
        observing: true,
        onEvent: (_) {},
        onEmote: (_) {},
        networkEmote: serial == 0 ? null : '😏',
        networkEmoteSerial: serial,
        networkEmoteSeat: 1,
      ),
    );
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(screen(0));
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(screen(1));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('player-emote-1')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is GameEmoteIcon &&
            widget.emoji == '😏' &&
            widget.size == 94,
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is GameEmoteIcon &&
            widget.emoji == '😏' &&
            widget.size == 32,
      ),
      findsOneWidget,
    );
    final toast = find.byKey(const ValueKey('match-activity-notice'));
    expect(toast, findsOneWidget);
    expect(
      tester.getTopLeft(toast).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const ValueKey('player-tile-1'))).dy,
      ),
    );
    expect(
      tester.getCenter(toast).dx,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('top-reaction-toast'))).dx,
        1,
      ),
    );
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(640, 320), const Size(844, 390)]) {
    testWidgets('landscape emotes fit without borders at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final state = tableWithSupplies();
      Widget screen(int serial, String? emoji) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'NotoSans', brightness: Brightness.dark),
        home: MatchView(
          state: state,
          online: true,
          viewingSeat: 0,
          observing: true,
          onEvent: (_) {},
          onEmote: (_) {},
          networkEmote: emoji,
          networkEmoteSerial: serial,
          networkEmoteSeat: 1,
        ),
      );
      await tester.runAsync(loadTabletopArt);
      await tester.pumpWidget(screen(0, null));
      final slot = find.byKey(const ValueKey('player-emote-1'));
      final tile = find.byKey(const ValueKey('player-tile-1'));
      final shield = find
          .descendant(of: tile, matching: find.byType(Icon))
          .first;
      var serial = 0;
      for (final emoji in ['😄', '😤', '😏', '👏', '🤝', '👋']) {
        await tester.pumpWidget(screen(++serial, emoji));
        await tester.pump(const Duration(milliseconds: 250));
        final icon = find.descendant(
          of: slot,
          matching: find.byWidgetPredicate(
            (widget) => widget is GameEmoteIcon && widget.emoji == emoji,
          ),
        );
        expect(icon, findsOneWidget);
        final fitted = find
            .ancestor(of: icon, matching: find.byType(FittedBox))
            .first;
        final rect = tester.getRect(fitted);
        final bounds = tester.getRect(tile);
        expect(rect.top, greaterThanOrEqualTo(bounds.top));
        expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
        expect(rect.overlaps(tester.getRect(shield)), isFalse);
        expect(
          find.descendant(of: slot, matching: find.byType(DecoratedBox)),
          findsNothing,
        );
        expect(tester.widget<FittedBox>(fitted).fit, BoxFit.scaleDown);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('another player discards with a comic insult', (tester) async {
    final before = MatchEngine.newGame(['Alex', 'Mira', 'Sam'], 901);
    final after = before.copyWith(
      events: [
        ...before.events,
        DiscardResources(1, {Resource.wheat: 3}),
      ],
    );
    Widget screen(MatchState state) => MaterialApp(
      theme: ThemeData(fontFamily: 'NotoSans', brightness: Brightness.dark),
      home: Scaffold(body: MatchActivity(state: state, viewerSeat: 0)),
    );
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(screen(before));
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(screen(after));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Mira'), findsOneWidget);
    expect(find.textContaining('mugged'), findsOneWidget);
    expect(find.textContaining('3 resources gone'), findsOneWidget);
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('blocked bandit displays its humiliation on the board', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final original = tableWithSupplies();
    final tile = original.board.tiles.indexWhere(
      (t) => t.productionNumber != null,
    );
    expect(tile, isNonNegative);
    final number = original.board.tiles[tile].productionNumber!;
    final before = original.copyWith(banditTile: tile);
    final after = before.copyWith(
      dice: number,
      events: [...before.events, RollDice(number ~/ 2, number - number ~/ 2)],
    );
    Widget screen(MatchState state) => MaterialApp(
      theme: ThemeData(fontFamily: 'NotoSans', brightness: Brightness.dark),
      home: MatchView(state: state, onEvent: (_) {}, observing: true),
    );
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(screen(before));
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(screen(after));
    await tester.pump(const Duration(milliseconds: 1150));
    await expectLater(
      find.byKey(const ValueKey('realm-map')),
      matchesGoldenFile('goldens/bandit_denied.png'),
    );
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(const SizedBox());
  });
}
