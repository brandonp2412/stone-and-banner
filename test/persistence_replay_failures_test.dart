import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'valid imported replay never silently overwrites local progress',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var original = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 17001);
      original = MatchEngine.apply(
        original,
        PlaceVillage(MatchEngine.legalVertices(original).first),
      );
      final oldReplay = MatchEngine.exportReplay(original);
      final imported = MatchEngine.newGame(['Zoe', 'Yan', 'Xan'], 17002);
      final newReplay = MatchEngine.exportReplay(imported);
      SharedPreferences.setMockInitialValues({
        'stone_banner_local_replay_v1': oldReplay,
        'stone_banner_local_session_v2': jsonEncode({
          'version': 2,
          'replay': oldReplay,
          'computerSeats': [1, 2],
        }),
      });

      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      expect(find.text('Continue saved match'), findsOneWidget);

      Future<void> enterReplay() async {
        await tester.tap(find.text('Import replay'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, newReplay);
        await tester.tap(find.text('Load'));
        await tester.pumpAndSettle();
      }

      await enterReplay();
      expect(find.text('Replace saved match?'), findsOneWidget);
      expect(find.textContaining('hot-seat mode'), findsOneWidget);
      await tester.tap(find.text('Keep saved match'));
      await tester.pumpAndSettle();
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('stone_banner_local_replay_v1'), oldReplay);
      expect(find.text('Continue saved match'), findsOneWidget);

      await enterReplay();
      await tester.tap(find.text('Import and replace'));
      await tester.pumpAndSettle();
      expect(find.text('Pass the device'), findsOneWidget);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('stone_banner_local_replay_v1'), newReplay);
      final session = jsonDecode(
        prefs.getString('stone_banner_local_session_v2')!,
      ) as Map<String, dynamic>;
      expect(session['computerSeats'], isEmpty);
      expect(
        MatchEngine.snapshot(
          MatchEngine.importReplay(session['replay'] as String),
        ),
        MatchEngine.snapshot(imported),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue saved match'));
      await tester.pumpAndSettle();
      expect(find.text('Pass the device'), findsOneWidget);
    },
  );

  testWidgets('invalid import preserves an existing saved AI session', (
    tester,
  ) async {
    final original = MatchEngine.exportReplay(
      MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 17003),
    );
    SharedPreferences.setMockInitialValues({
      'stone_banner_local_replay_v1': original,
      'stone_banner_local_session_v2': jsonEncode({
        'version': 2,
        'replay': original,
        'computerSeats': [1, 2],
      }),
    });
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Import replay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import replay'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'sbz1:invalid!');
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    expect(find.text('Replace saved match?'), findsNothing);
    expect(find.textContaining('Invalid replay code'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('stone_banner_local_replay_v1'), original);
    final session = jsonDecode(
      prefs.getString('stone_banner_local_session_v2')!,
    ) as Map<String, dynamic>;
    expect(session['computerSeats'], [1, 2]);
  });

  testWidgets('corrupt session metadata falls back to legacy replay', (
    tester,
  ) async {
    final original = MatchEngine.exportReplay(
      MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 17004),
    );
    SharedPreferences.setMockInitialValues({
      'stone_banner_local_replay_v1': original,
      'stone_banner_local_session_v2': '{corrupt',
    });
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    expect(find.text('Continue saved match'), findsOneWidget);
    await tester.tap(find.text('Continue saved match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);
  });
}
