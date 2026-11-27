import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

MatchState finishedFor(int winner) {
  final initial = tableWithSupplies();
  final players = initial.players.toList();
  players[winner] = players[winner].copyWith(guardianHonour: 13);
  final state = initial.copyWith(players: players, phase: MatchPhase.finished);
  assert(MatchEngine.winner(state) == winner);
  return state;
}

Future<void> setup(WidgetTester tester) async {
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
}

void main() {
  testWidgets(
    'victory animates in, can review and reopen without changing match',
    (tester) async {
      await setup(tester);
      var state = tableWithSupplies();
      late StateSetter refresh;
      var homeTapped = false;
      await tester.runAsync(loadTabletopArt);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: 'NotoSans',
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                refresh = update;
                return MatchView(
                  state: state,
                  computerSeats: const {1, 2, 3},
                  visibleSeat: 0,
                  onEvent: (_) {},
                  onHome: () => homeTapped = true,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('match-finale-dialog')), findsNothing);
      refresh(() => state = finishedFor(0));
      await tester.pump();
      expect(find.byKey(const ValueKey('match-finale-dialog')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1250));
      expect(find.text('VICTORY'), findsOneWidget);
      expect(find.text('Ada claims the realm'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/end_game_victory.png'),
      );
      await tester.tap(find.byKey(const ValueKey('match-finale-review')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('match-finale-dialog')), findsNothing);
      expect(find.byKey(const ValueKey('reopen-match-finale')), findsOneWidget);
      expect(state.phase, MatchPhase.finished);
      await tester.tap(find.byKey(const ValueKey('reopen-match-finale')));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('VICTORY'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('match-finale-home')));
      expect(homeTapped, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(360, 780),
    const Size(780, 360),
    const Size(1280, 720),
  ]) {
    testWidgets('review results has its own space at $size', (tester) async {
      await setup(tester);
      tester.view.physicalSize = size;
      await tester.runAsync(loadTabletopArt);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: 'NotoSans',
          ),
          home: Scaffold(
            body: MatchView(
              state: finishedFor(0),
              visibleSeat: 0,
              onEvent: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.tap(find.byKey(const ValueKey('match-finale-review')));
      await tester.pump(const Duration(milliseconds: 200));
      final results = find.byKey(const ValueKey('reopen-match-finale'));
      final board = find.byKey(const ValueKey('realm-map'));
      expect(results.hitTestable(), findsOneWidget);
      expect(tester.getRect(results).overlaps(tester.getRect(board)), isFalse);
      expect(
        tester
            .getRect(results)
            .overlaps(
              tester.getRect(find.byKey(const ValueKey('raid-defense-hud'))),
            ),
        isFalse,
      );
      if (size.width < 900) {
        final actions = find.byKey(const ValueKey('mobile-open-actions'));
        expect(actions.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(results).overlaps(tester.getRect(actions)),
          isFalse,
        );
      }
      await tester.tap(results);
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.byKey(const ValueKey('match-finale-dialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('AI win shows animated defeat for human viewer', (tester) async {
    await setup(tester);
    final state = finishedFor(1);
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
            state: state,
            computerSeats: const {1, 2, 3},
            visibleSeat: 0,
            onEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text('DEFEAT'), findsOneWidget);
    expect(find.text('Ben claims the realm'), findsOneWidget);
    expect(find.text('VICTORY'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/end_game_defeat.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hot-seat final result celebrates the winning player', (
    tester,
  ) async {
    await setup(tester);
    final state = finishedFor(2);
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MatchView(state: state, onEvent: (_) {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('VICTORY'), findsOneWidget);
    expect(find.text('Cora claims the realm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact result fits 640×320 and larger text without overflow', (
    tester,
  ) async {
    await setup(tester);
    tester.view.physicalSize = const Size(640, 320);
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'NotoSans',
        ),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(640, 320),
            textScaler: TextScaler.linear(1.45),
          ),
          child: Scaffold(
            body: MatchView(
              state: finishedFor(0),
              computerSeats: const {1, 2},
              visibleSeat: 0,
              onEvent: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text('VICTORY'), findsOneWidget);
    expect(find.byKey(const ValueKey('match-finale-review')), findsOneWidget);
    final dialog = find.byKey(const ValueKey('match-finale-dialog'));
    final scoreViewport = find.descendant(
      of: dialog,
      matching: find.byType(Scrollable),
    );
    expect(scoreViewport, findsOneWidget);
    final viewport = tester.getRect(scoreViewport);
    for (final name in ['Ada', 'Ben', 'Cora', 'Dee']) {
      final row = find.descendant(of: dialog, matching: find.text(name));
      expect(row, findsOneWidget);
      expect(
        tester.getRect(row).bottom,
        lessThanOrEqualTo(viewport.bottom),
        reason: '$name score must not be clipped at 145% text scale',
      );
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/end_game_compact.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('finale entrance and particle layer animate', (tester) async {
    await setup(tester);
    await tester.runAsync(loadTabletopArt);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: MatchView(state: finishedFor(0), onEvent: (_) {}),
        ),
      ),
    );
    await tester.pump();
    final dialog = find.byKey(const ValueKey('match-finale-dialog'));
    expect(dialog, findsOneWidget);
    final firstOpacity = tester
        .widgetList<Opacity>(
          find.ancestor(of: dialog, matching: find.byType(Opacity)),
        )
        .first
        .opacity;
    await tester.pump(const Duration(milliseconds: 480));
    final secondOpacity = tester
        .widgetList<Opacity>(
          find.ancestor(of: dialog, matching: find.byType(Opacity)),
        )
        .first
        .opacity;
    expect(secondOpacity, greaterThan(firstOpacity));
    await tester.pump(const Duration(milliseconds: 740));
    expect(find.byKey(const ValueKey('match-finale-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
