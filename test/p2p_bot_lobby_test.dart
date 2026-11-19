import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/p2p_room.dart';

void main() {
  test(
    'one host can fill remaining three-player lobby with solo-game bots',
    () async {
      final room = P2pRoom(botMoveDelay: const Duration(milliseconds: 2));
      addTearDown(room.dispose);
      room.host('Host', 3, 42);
      expect(room.canStart, false);
      expect(room.availableBotSeats, 2);
      room.setBotCount(2);
      expect(room.botSeats, {1, 2});
      expect(room.canStart, true);
      room.start();
      expect(room.started, true);
      expect(room.botCount, 2);
      expect(room.players.length, 3);
      expect(room.connectedPlayers, [true, true, true]);
      expect(room.game!.players.length, 3);
      expect(room.aiMoveCount, 0);
      expect(room.players[1], isNot('Host'));

      room.dispatch(PlaceVillage(MatchEngine.legalVertices(room.game!).first));
      room.dispatch(PlaceRoad(MatchEngine.legalEdges(room.game!).first));
      await room.aiSettled.timeout(const Duration(seconds: 20));
      expect(
        room.aiError,
        isNull,
        reason: 'Local HeuristicAi must be reusable in P2P',
      );
      expect(room.aiMoveCount, greaterThanOrEqualTo(4));
      expect(
        room.game!.events.length,
        0,
        reason: 'Private multiplayer views exclude replay events',
      );
      expect(
        room.game!.actingSeat,
        0,
        reason: 'AI should return the turn to the human host',
      );
    },
  );

  test(
    'bot reservation can be adjusted and does not create players until start',
    () {
      final room = P2pRoom(botMoveDelay: Duration.zero);
      addTearDown(room.dispose);
      room.host('Host', 4, 100);
      room.setBotCount(2);
      expect(room.botSeats, {1, 2});
      expect(room.players, ['Host']);
      expect(room.canStart, false);
      room.setBotCount(3);
      expect(room.botSeats, {1, 2, 3});
      expect(room.canStart, true);
      room.setBotCount(0);
      expect(room.botSeats, isEmpty);
      expect(room.canStart, false);
      expect(() => room.setBotCount(4), throwsStateError);
      expect(room.players, ['Host']);
    },
  );

  test('only host may manage bot seats', () {
    final guest = P2pRoom();
    addTearDown(guest.dispose);
    expect(() => guest.setBotCount(1), throwsStateError);
    expect(guest.botSeats, isEmpty);
  });

  test('four-player lobby supports three bots with no network transport', () {
    final room = P2pRoom(botMoveDelay: Duration.zero);
    addTearDown(room.dispose);
    room.host('Host', 4, 50);
    room.setBotCount(3);
    room.start();
    expect(room.botSeats, {1, 2, 3});
    expect(room.players.length, 4);
    expect(room.connectedPlayers.every((v) => v), true);
    expect(room.canStart, false);
    expect(() => room.setBotCount(0), throwsStateError);
  });
}
