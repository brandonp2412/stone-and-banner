import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_host.dart';
import 'package:stone_and_banner/ui/match_end_modal.dart';

void main() {
  testWidgets(
    'completed saved solo match rematches directly with same players and difficulty',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final room = HostedRoom.restored('AABBCCDD', 3, 8700, 20261125);
      for (final name in ['Host', 'Alder', 'Briar']) {
        room.join(name);
      }
      room.start(0);
      const bot = HeuristicAi();
      for (
        var step = 0;
        step < 6000 && room.state!.phase != MatchPhase.finished;
        step++
      ) {
        final before = room.state!;
        final event = bot.choose(before)!;
        final seat = event is RespondTrade ? event.player : before.actingSeat;
        final reply = room.move(
          seat,
          'rematch-$step',
          room.version,
          event.toJson(),
        );
        expect(reply['ok'], true);
      }
      final prior = room.state!;
      expect(prior.phase, MatchPhase.finished);
      final replay = MatchEngine.exportReplay(prior);
      SharedPreferences.setMockInitialValues({
        'stone_banner_local_replay_v1': replay,
        'stone_banner_local_session_v2': jsonEncode({
          'version': 2,
          'replay': replay,
          'computerSeats': [1, 2],
          'botDifficulty': 'easy',
        }),
      });
      await tester.runAsync(loadTabletopArt);
      await tester.pumpWidget(
        StoneBannerApp(
          worldSeedFactory: () => 123456,
          randomizeTurnOrder: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Play again'), findsOneWidget);
      await tester.tap(find.text('Play again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Play again'), findsNothing);
      final view = tester.widget<MatchView>(find.byType(MatchView));
      expect(view.state.phase, MatchPhase.setupVillage);
      expect(view.state.seed, 123456);
      expect(
        view.state.players.map((p) => p.id),
        prior.players.map((p) => p.id),
      );
      expect(view.computerSeats, {1, 2});
      final prefs = await SharedPreferences.getInstance();
      final session =
          jsonDecode(prefs.getString('stone_banner_local_session_v2')!) as Map;
      expect(session['botDifficulty'], 'easy');
      expect(
        MatchEngine.importReplay(session['replay'] as String).seed,
        123456,
      );
      await tester.runAsync(loadTabletopArt);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'only host can rematch finished rooms; keeps seats and resets state',
    () {
      final room = LanRoomRegistry().create(3, 42, 'Ada');
      room.join('Ben');
      room.join('Cora');
      room.start(0);
      expect(() => room.playAgain(0), throwsStateError);
      final old = room.state!;
      final tokens = room.seats.map((s) => s.token).toList();
      room.state = old.copyWith(phase: MatchPhase.finished);
      expect(() => room.playAgain(1), throwsStateError);
      room.playAgain(0);
      expect(room.generation, 1);
      expect(room.state!.phase, MatchPhase.setupVillage);
      expect(room.state!.seed, isNot(old.seed));
      expect(room.state!.players.map((p) => p.id), ['Ada', 'Ben', 'Cora']);
      expect(room.seats.map((s) => s.token), tokens);
      expect(room.version, 0);
      expect(room.historyAfter(0), isEmpty);
      expect(HostedRoom.fromPrivateJson(room.toPrivateJson()).generation, 1);
    },
  );
  for (final size in [const Size(640, 320), const Size(393, 852)]) {
    for (final victory in [true, false]) {
      testWidgets('rematch $size $victory', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('NotoSans')
              ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        var tapped = false;
        await tester.runAsync(loadTabletopArt);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'NotoSans',
              ),
            ),
            home: Scaffold(
              body: MatchEndModal(
                state: MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 42),
                winner: victory ? 0 : 1,
                victory: victory,
                onReview: () {},
                onHome: () {},
                onPlayAgain: () => tapped = true,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1200));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/rematch_${size.width.toInt()}_$victory.png',
          ),
        );
        await tester.tap(find.text('Play again'));
        expect(tapped, isTrue);
      });
    }
  }
}
