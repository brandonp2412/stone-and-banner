import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

void main() {
  for (final variant in <(Size, double)>[
    (const Size(320, 640), 1.6),
    (const Size(390, 844), 2.0),
    (const Size(800, 360), 1.5),
  ]) {
    testWidgets('readable game phase headers at $variant', (tester) async {
      tester.view.physicalSize = variant.$1;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = variant.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final initial = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 44);
      for (final (phase, label) in <(MatchPhase, String)>[
        (MatchPhase.setupVillage, 'Place village'),
        (MatchPhase.setupRoad, 'Place road'),
        (MatchPhase.roll, 'Roll dice'),
        (MatchPhase.actions, 'Your turn'),
        (MatchPhase.bandit, 'Move Bandit'),
        (MatchPhase.invasion, 'Defend realm'),
        (MatchPhase.finished, 'Game over'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MatchView(
                state: initial.copyWith(phase: phase),
                onEvent: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Round 1 · $label'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'Phase $label overflowed at ${variant.$1} and ${variant.$2}x',
        );
      }
    });
  }

  testWidgets('setup board target is reachable through semantics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 44),
            onEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Choose board target from list'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Choose board target from list'));
    await tester.pumpAndSettle();
    expect(find.text('Choose legal board target'), findsOneWidget);
    expect(find.textContaining('Junction 1:'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('replay dialog keeps helper readable at narrow large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Import replay'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import replay'));
    await tester.pumpAndSettle();
    expect(find.text('JSON and compact share codes work'), findsOneWidget);
    expect(find.text('Replay code'), findsOneWidget);
    expect(find.text('Load'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
