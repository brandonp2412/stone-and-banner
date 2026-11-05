import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/replay_codes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Map<String, dynamic>> session() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString('stone_banner_local_session_v2')!)
        as Map<String, dynamic>;
  }

  Future<void> configureFourSeats(WidgetTester tester, int botCount) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vs AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 players'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('$botCount AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$botCount AI'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '${4 - botCount} human${botCount == 3 ? '' : 's'} · '
        '$botCount computer · seeded offline strategy',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Start match'));
    await tester.tap(find.text('Start match'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> chooseFirstLegalTarget(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Choose board target from list'));
    await tester.tap(find.text('Choose board target from list'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
  }

  testWidgets('four seats with three AIs finish automatic snake setup, '
      'survive leaving and process-like restart without replay drift', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await configureFourSeats(tester, 3);
    var saved = await session();
    expect(saved['computerSeats'], [1, 2, 3]);
    expect(
      MatchEngine.importReplay(saved['replay'] as String).players.length,
      4,
    );
    expect(find.text('Pass the device'), findsNothing);

    await chooseFirstLegalTarget(tester);
    await chooseFirstLegalTarget(tester);
    expect(find.text('Computer turn'), findsOneWidget);
    expect(find.text('Your goods'), findsNothing);

    MatchState? state;
    for (var tick = 0; tick < 350; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
      saved = await session();
      state = MatchEngine.importReplay(saved['replay'] as String);
      if (state.active == 0 &&
          state.events.length >= 14 &&
          find.text('Computer turn').evaluate().isEmpty) {
        break;
      }
    }
    expect(state, isNotNull);
    expect(state!.active, 0);
    expect(state.events.length, greaterThanOrEqualTo(14));
    expect(state.phase, MatchPhase.setupVillage);
    expect(find.text('Pass the device'), findsNothing);
    expect(find.text('Choose board target from list'), findsOneWidget);
    final replay = saved['replay'] as String;
    expect(
      MatchEngine.snapshot(
        MatchEngine.importReplay(
          ReplayCodes.expand(ReplayCodes.compact(replay)),
        ),
      ),
      MatchEngine.snapshot(state),
    );

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Continue saved match'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue saved match'));
    await tester.pump();
    expect(find.text('Computer turn'), findsNothing);
    expect(find.text('Pass the device'), findsNothing);
    expect(find.text('Choose board target from list'), findsOneWidget);
    final after = await session();
    expect(after['computerSeats'], [1, 2, 3]);
    expect(after['replay'], replay);
  });

  testWidgets('four-player computer draft pauses during app suspension '
      'and resumes without duplicating events', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await configureFourSeats(tester, 3);
    await chooseFirstLegalTarget(tester);
    await chooseFirstLegalTarget(tester);
    expect(find.text('Computer turn'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = await session();
    final eventCount = MatchEngine.importReplay(paused['replay'] as String)
        .events
        .length;
    await tester.pump(const Duration(seconds: 2));
    final stillPaused = await session();
    expect(
      MatchEngine.importReplay(stillPaused['replay'] as String).events.length,
      eventCount,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    MatchState? resumed;
    for (var tick = 0; tick < 350; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
      final current = await session();
      resumed = MatchEngine.importReplay(current['replay'] as String);
      if (resumed.active == 0 &&
          resumed.events.length >= 14 &&
          find.text('Computer turn').evaluate().isEmpty) {
        break;
      }
    }
    expect(resumed, isNotNull);
    expect(resumed!.events.length, 14);
    expect(resumed.active, 0);
  });

  for (final botCount in [1, 2]) {
    testWidgets('four seats with $botCount AI preserve private handoff '
        'and AI assignment across widget restart', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await configureFourSeats(tester, botCount);
      expect(find.text('Pass the device'), findsOneWidget);
      expect(find.text('Your goods'), findsNothing);
      final before = await session();
      expect(before['computerSeats'], [
        for (var seat = 4 - botCount; seat < 4; seat++) seat,
      ]);
      final initial = MatchEngine.importReplay(before['replay'] as String);
      expect(initial.players.length, 4);
      expect(initial.events, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue saved match'));
      await tester.pump();
      expect(find.text('Pass the device'), findsOneWidget);
      expect(find.text('Your goods'), findsNothing);
      final after = await session();
      expect(after['replay'], before['replay']);
      expect(after['computerSeats'], before['computerSeats']);
    });
  }
}
