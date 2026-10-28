import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'accessible legal target list places and restores a private match',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'm ready"));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Choose board target from list'));
      await tester.tap(find.text('Choose board target from list'));
      await tester.pumpAndSettle();
      expect(find.text('Choose legal board target'), findsOneWidget);
      expect(find.textContaining('Junction 1:'), findsWidgets);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('glowing side'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      final replay = prefs.getString('stone_banner_local_replay_v1');
      expect(replay, isNotNull);
      final restored = MatchEngine.importReplay(replay!);
      expect(restored.events.length, 1);
      expect(restored.phase, MatchPhase.setupRoad);
      expect(MatchEngine.score(restored, 0), 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      expect(find.text('Continue saved match'), findsOneWidget);
      await tester.tap(find.text('Continue saved match'));
      await tester.pumpAndSettle();
      expect(find.text('Pass the device'), findsOneWidget);
      expect(find.textContaining('glowing side'), findsNothing);
      await tester.tap(find.text("I'm ready"));
      await tester.pumpAndSettle();
      expect(find.textContaining('glowing side'), findsOneWidget);

      await tester.ensureVisible(find.text('Choose board target from list'));
      await tester.tap(find.text('Choose board target from list'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Road '), findsWidgets);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      final later = MatchEngine.importReplay(
        (await SharedPreferences.getInstance()).getString(
          'stone_banner_local_replay_v1',
        )!,
      );
      expect(later.events.length, 2);
      expect(later.phase, MatchPhase.setupVillage);

      await tester.tap(find.byIcon(Icons.home_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.hexagon_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Pass the device'), findsOneWidget);
    },
  );

  testWidgets('corrupt local save is rejected without revealing the match', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'stone_banner_local_replay_v1': 'untrusted replay',
    });
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue saved match'));
    await tester.pump();
    expect(find.textContaining('Saved replay is invalid'), findsOneWidget);
    expect(find.text('Pass the device'), findsNothing);
  });
}
