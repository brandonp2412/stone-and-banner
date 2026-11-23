import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/engine/match.dart';

import 'dart:convert';

import 'package:stone_and_banner/network/p2p_room.dart';
import 'package:stone_and_banner/network/room_host.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

void main() {
  for (final count in [5, 6]) {
    test('$count-player room starts and restores its checkpoint', () {
      final room = LanRoomRegistry().create(count, 42, 'Player 1');
      for (var seat = 2; seat <= count; seat++) {
        room.join('Player $seat');
      }
      room.start(0);
      final restored = HostedRoom.fromPrivateJson(room.toPrivateJson());
      expect(restored.capacity, count);
      expect(restored.state!.players.length, count);
      expect(() => restored.join('Extra'), throwsStateError);
    });

    test('$count-player P2P lobby supports bots in every remaining seat', () {
      final room = P2pRoom(botMoveDelay: Duration.zero);
      addTearDown(room.dispose);
      room.host('Host', count, 42);
      expect(room.availableBotSeats, count - 1);
      room.setBotCount(count - 1);
      expect(room.canStart, true);
      room.start();
      expect(room.game!.players.length, count);
      expect(room.botSeats.length, count - 1);
    });

    testWidgets('$count-player local setup starts with all human names', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const StoneBannerApp(randomizeTurnOrder: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New local match'));
      await tester.pumpAndSettle();
      for (final seats in [3, 4, 5, 6]) {
        expect(find.text('$seats players'), findsOneWidget);
      }
      await tester.ensureVisible(find.text('$count players'));
      await tester.tap(find.text('$count players'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start match'));
      await tester.tap(find.text('Start match'));
      await tester.pumpAndSettle();
      expect(find.text('Pass the device'), findsOneWidget);
      expect(seatColors.take(count).toSet().length, count);
      final prefs = await SharedPreferences.getInstance();
      final session = jsonDecode(
        prefs.getString('stone_banner_local_session_v2')!,
      ) as Map<String, dynamic>;
      expect(
        MatchEngine.importReplay(session['replay'] as String).players.length,
        count,
      );
      await tester.tap(find.text("I'm ready"));
      await tester.pumpAndSettle();
      expect(find.byType(MatchView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
