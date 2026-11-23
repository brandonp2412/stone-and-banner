import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/match_archive.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/match_end_modal.dart';
import 'package:stone_and_banner/ui/gameplay_hint.dart';
import 'package:stone_and_banner/ui/match_history.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

Future<void> capture(WidgetTester tester, String path) async {
  final boundary = tester.renderObject(
    find.byKey(const ValueKey('capture')),
  ) as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await loader.load();
  });
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_seen_v1': gameplayHints.keys.toList(),
    }),
  );

  testWidgets(
    'new card banner visible while bot acts and Realm stays on viewer',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var state = tableWithSupplies();
      Widget app() => MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Scaffold(
            body: MatchView(
              state: state,
              visibleSeat: 0,
              observing: false,
              computerSeats: const {1, 2, 3},
              onEvent: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 300));
      final cards = [
        ...state.players[0].cards,
        const HeldCard(StrategyDeck.commerce, 0),
      ];
      final players = [...state.players];
      players[0] = players[0].copyWith(cards: cards);
      state = state.copyWith(players: players, active: 1);
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 750));
      expect(
        find.byKey(const ValueKey('card-received-banner')),
        findsOneWidget,
      );
      expect(find.text('NEW STRATEGY CARD!'), findsOneWidget);
      if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
        await tester.runAsync(
          () => capture(tester, '/tmp/stone-card-receipt-ui.png'),
        );
      }
    },
  );

  testWidgets('free road card selects a glowing map edge, not an edge list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = tableWithSupplies().copyWith(cardDeckVersion: 2);
    final deck = StrategyCards.expandedDeck(StrategyDeck.innovation);
    final index = deck.indexWhere((card) => card.id == 'surveyor');
    final players = state.players.toList();
    players[0] = players[0].copyWith(
      cards: [HeldCard(StrategyDeck.innovation, index)],
    );
    state = state.copyWith(players: players);
    final options = MatchEngine.legalCardPlays(state, 0);
    expect(options, isNotEmpty);
    MatchEvent? played;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('capture'),
            child: MatchView(
              state: state,
              visibleSeat: 0,
              onEvent: (event) => played = event,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Cards').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Surveyor').last);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.textContaining('Lay one connected road'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Choose on map'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey('choose-card-target-on-map')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
    if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
      await tester.runAsync(
        () => capture(tester, '/tmp/stone-map-card-target-ui.png'),
      );
    }
    expect(find.textContaining('edge '), findsNothing);
    final surface = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('realm-map')),
    );
    final geometry = BoardGeometry(surface.size);
    final edge = state.topology.edges[options.first.vertex!];
    final localPosition =
        (geometry.vertex(state.topology.vertices[edge.a]) +
            geometry.vertex(state.topology.vertices[edge.b])) /
        2;
    await tester.tapAt(surface.localToGlobal(localPosition));
    await tester.pump(const Duration(milliseconds: 200));
    expect(played, isA<PlayStrategyCard>());
    expect((played as PlayStrategyCard).vertex, options.first.vertex);
  });

  testWidgets('victory wraps all four player names without clipping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 415);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = MatchEngine.newGame([
      'Princess Adelaide of Westvale',
      'Oswin the Bold',
      'Brianna of Ashvale',
      'Tamsin Oakbanner of the North',
    ], 2115);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('capture'),
            child: MatchEndModal(
              state: state,
              winner: 0,
              victory: true,
              onReview: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final dialog = tester.getRect(
      find.byKey(const ValueKey('match-finale-dialog')),
    );
    final finalPlayer = find.text('Tamsin Oakbanner of the North');
    expect(finalPlayer, findsOneWidget);
    final lastRect = tester.getRect(finalPlayer);
    expect(lastRect.right, lessThanOrEqualTo(dialog.right));
    expect(lastRect.bottom, lessThanOrEqualTo(dialog.bottom));
    expect(tester.widget<Text>(finalPlayer).maxLines, 2);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
      await tester.runAsync(
        () => capture(tester, '/tmp/stone-finale-wrapped-ui.png'),
      );
    }
  });

  testWidgets('player and bank trade controls do not shift when switching', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = tableWithSupplies();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        builder: (context, child) =>
            RepaintBoundary(key: const ValueKey('capture'), child: child!),
        home: Scaffold(
          body: MatchView(state: state, visibleSeat: 0, onEvent: (_) {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Trade').last);
    await tester.pump(const Duration(milliseconds: 420));
    await tester.tap(find.text('Player trade'));
    await tester.pump(const Duration(milliseconds: 420));
    final segment = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith('SegmentedButton<'),
    );
    expect(segment, findsOneWidget);
    final controlsBefore = tester.getRect(segment);
    final giveBefore = tester.getRect(find.text('YOU GIVE').first);
    if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
      await tester.runAsync(
        () => capture(tester, '/tmp/stone-trade-player-ui.png'),
      );
    }
    await tester.tap(find.text('Bank').last);
    await tester.pump(const Duration(milliseconds: 420));
    final controlsAfter = tester.getRect(segment);
    final giveAfter = tester.getRect(find.text('YOU GIVE').first);
    expect((controlsAfter.left - controlsBefore.left).abs(), lessThan(1));
    expect((controlsAfter.width - controlsBefore.width).abs(), lessThan(1));
    expect((giveAfter.top - giveBefore.top).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
      await tester.runAsync(
        () => capture(tester, '/tmp/stone-trade-bank-ui.png'),
      );
    }
  });

  testWidgets(
    'archived game rows load without merging replay blobs into index',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      final s = MatchEngine.apply(
        MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 333),
        const PlaceVillage(0),
      );
      await MatchArchive.save(prefs, s);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: MatchHistoryPage(prefs: prefs),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ada vs Ben vs Cora'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
        await tester.runAsync(
          () => capture(tester, '/tmp/stone-match-history-ui.png'),
        );
      }
    },
  );
}
