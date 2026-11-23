import 'dart:convert';

import 'board_target_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );

  testWidgets('board selection places and restores a private match', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StoneBannerApp(randomizeTurnOrder: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm ready"));
    await tester.pumpAndSettle();

    final initialPrefs = await SharedPreferences.getInstance();
    final initial = MatchEngine.importReplay(
      initialPrefs.getString('stone_banner_local_replay_v1')!,
    );
    await tapBoardTarget(tester, initial);

    final prefs = await SharedPreferences.getInstance();
    final replay = prefs.getString('stone_banner_local_replay_v1');
    expect(replay, isNotNull);
    final restored = MatchEngine.importReplay(replay!);
    expect(restored.events.length, 1);
    expect(restored.phase, MatchPhase.setupRoad);
    expect(MatchEngine.score(restored, 0), 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const StoneBannerApp(randomizeTurnOrder: false));
    await tester.pumpAndSettle();
    expect(find.text('Continue saved match'), findsOneWidget);
    expect(find.text('Pass the device'), findsNothing);
    expect(find.byKey(const ValueKey('realm-map')), findsNothing);
    await tester.tap(find.text('Continue saved match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);
    expect(find.byKey(const ValueKey('realm-map')), findsNothing);
    await tester.tap(find.text("I'm ready"));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Choose target'), findsNothing);

    await tapBoardTarget(tester, restored);
    final later = MatchEngine.importReplay(
      (await SharedPreferences.getInstance()).getString(
        'stone_banner_local_replay_v1',
      )!,
    );
    expect(later.events.length, 2);
    expect(later.phase, MatchPhase.setupVillage);

    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue saved match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);
  });

  testWidgets('corrupt local save is rejected without revealing the match', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'stone_banner_local_replay_v1': 'untrusted replay',
    });
    await tester.pumpWidget(const StoneBannerApp(randomizeTurnOrder: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved replay is invalid'), findsOneWidget);
    expect(find.text('Pass the device'), findsNothing);
  });

  testWidgets('a saved match with two humans and a bot launches at home', (
    tester,
  ) async {
    final replay = MatchEngine.exportReplay(
      MatchEngine.newGame(['Ada', 'Ben', 'Bot'], 17003),
    );
    final session = jsonEncode({
      'version': 2,
      'replay': replay,
      'computerSeats': [2],
    });
    SharedPreferences.setMockInitialValues({
      'stone_banner_local_session_v2': session,
    });
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    expect(find.text('Continue saved match'), findsOneWidget);
    expect(find.text('Pass the device'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('stone_banner_local_session_v2'), session);

    await tester.tap(find.text('Continue saved match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);
  });
}
