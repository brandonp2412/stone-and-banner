import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/simulation.dart';
import 'package:stone_and_banner/ui/match_history.dart';
import 'package:stone_and_banner/match_archive.dart';
import 'package:stone_and_banner/ui/dice_roll.dart';
import 'package:stone_and_banner/ui/match_end_modal.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;
import 'match_end_modal_test.dart' show finishedFor, setup;

Future<void> capture(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject(
      find.byKey(const ValueKey('capture')),
    ) as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );

  testWidgets(
    'skip suppresses bot dice and preserves human dice across handoff',
    (tester) async {
      await setup(tester);
      var state = tableWithSupplies().copyWith(
        active: 1,
        phase: MatchPhase.roll,
      );
      var observing = true;
      var skipping = true;
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('capture'),
              child: StatefulBuilder(
                builder: (context, update) {
                  refresh = update;
                  return MatchView(
                    state: state,
                    observing: observing,
                    fastForwardingBots: skipping,
                    computerSeats: const {1, 2, 3},
                    visibleSeat: 0,
                    onEvent: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      refresh(
        () => state = state.copyWith(
          phase: MatchPhase.actions,
          dice: 5,
          events: [...state.events, const RollDice(2, 3)],
        ),
      );
      await tester.pump();
      expect(find.byType(DiceRoll), findsNothing);
      refresh(() {
        state = state.copyWith(active: 0, phase: MatchPhase.roll);
        observing = false;
        skipping = false;
      });
      await tester.pump();
      refresh(
        () => state = state.copyWith(
          phase: MatchPhase.actions,
          dice: 8,
          events: [...state.events, const RollDice(3, 5)],
        ),
      );
      await tester.pump();
      final dice = tester.state(find.byType(DiceRoll));
      await tester.pump(const Duration(milliseconds: 300));
      refresh(() => observing = true);
      await tester.pump();
      expect(tester.state(find.byType(DiceRoll)), same(dice));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('3 + 5 = 8'), findsOneWidget);
      await capture(tester, '/tmp/stone-dice-regression.png');
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(DiceRoll), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('finale remains mounted when road celebration disappears', (
    tester,
  ) async {
    await setup(tester);
    var state = finishedFor(0).copyWith(phase: MatchPhase.actions);
    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) {
              refresh = update;
              return MatchView(
                state: state,
                visibleSeat: 0,
                computerSeats: const {1, 2, 3},
                onEvent: (_) {},
              );
            },
          ),
        ),
      ),
    );
    refresh(
      () => state = state.copyWith(
        phase: MatchPhase.finished,
        crownRoadHolder: 0,
      ),
    );
    await tester.pump();
    final modal = tester.state(find.byType(MatchEndModal));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('VICTORY'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2200));
    expect(tester.state(find.byType(MatchEndModal)), same(modal));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reviewing a completed legacy archive displays defeat', (
    tester,
  ) async {
    await setup(tester);
    final prefs = await SharedPreferences.getInstance();
    final completed = List.generate(12, (i) => i + 1)
        .map((seed) => BalanceSimulation.run(seed: seed, maxRounds: 100))
        .firstWhere((match) => match.finished && match.winner != 0)
        .state;
    await MatchArchive.save(prefs, completed);
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
    expect(find.text('Review'), findsOneWidget);
    await tester.tap(find.text('Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('DEFEAT'), findsOneWidget);
    expect(find.text('VICTORY'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('legacy archive perspective displays defeat', (tester) async {
    await setup(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('capture'),
            child: MatchView(
              state: finishedFor(1),
              observing: true,
              visibleSeat: 0,
              viewingSeat: 0,
              onEvent: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text('DEFEAT'), findsOneWidget);
    expect(find.text('VICTORY'), findsNothing);
    await capture(tester, '/tmp/stone-history-defeat-regression.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('archive persists computer seats and accepts legacy entries', () async {
    final prefs = await SharedPreferences.getInstance();
    final state = tableWithSupplies();
    await MatchArchive.save(prefs, state, computerSeats: {1, 2, 3});
    final entry = (await MatchArchive.list(prefs)).single;
    expect(entry.computerSeats, {1, 2, 3});
    final legacy = entry.toJson()..remove('computerSeats');
    expect(ArchivedMatch.fromJson(legacy).computerSeats, isNull);
  });
}
