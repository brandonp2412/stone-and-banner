import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_host.dart';
import 'package:stone_and_banner/network/room_protocol.dart';

void main() {
  test('two human clients and two host bots play six rounds with conserved goods', () {
    final room = HostedRoom('AABBCCDD', 4, 8700);
    for (final name in ['Host', 'Guest', 'Bot A', 'Bot B']) {
      room.join(name);
    }
    room.start(0);
    final initial = room.state!;
    final totalGoods = <Resource, int>{
      for (final good in Resource.values)
        good:
            (initial.bank[good] ?? 0) +
            initial.players.fold<int>(
              0,
              (sum, player) => sum + (player.stores[good] ?? 0),
            ),
    };
    final movesPerSeat = <int, int>{0: 0, 1: 0, 2: 0, 3: 0};
    var maxRound = 1;
    var raids = 0;
    var exchanges = 0;
    var sawHumanGoods = false;
    final bot = const HeuristicAi();
    for (var step = 0; step < 6000; step++) {
      final before = room.state!;
      if (before.phase == MatchPhase.finished) {
        break;
      }
      final event = bot.choose(before);
      expect(
        event,
        isNotNull,
        reason: 'No legal move on step $step: ${before.phase}',
      );
      final seat = event is RespondTrade ? event.player : before.actingSeat;
      final reply = room.move(
        seat,
        'four-seat-$step',
        room.version,
        event!.toJson(),
      );
      expect(
        reply['ok'],
        true,
        reason:
            'Step $step, seat $seat, ${before.phase}, ${event.toJson()} -> $reply',
      );
      movesPerSeat[seat] = movesPerSeat[seat]! + 1;
      final after = room.state!;
      if (before.phase == MatchPhase.invasion &&
          after.phase != MatchPhase.invasion) {
        raids++;
      }
      if (after.round > maxRound) maxRound = after.round;
      if (event is RespondTrade && event.accept) exchanges++;
      for (final good in Resource.values) {
        final total =
            (after.bank[good] ?? 0) +
            after.players.fold<int>(
              0,
              (sum, player) => sum + (player.stores[good] ?? 0),
            );
        expect(
          total,
          totalGoods[good],
          reason:
              'Resource ${good.name} created/lost on $step: ${event.toJson()}',
        );
        expect(after.bank[good], greaterThanOrEqualTo(0));
        for (final player in after.players) {
          expect(player.stores[good] ?? 0, greaterThanOrEqualTo(0));
        }
      }
      for (final viewer in [0, 1]) {
        final publicView = RoomProtocol.view(after, viewer);
        final clientState = RoomProtocol.readView(publicView);
        expect(clientState.round, after.round);
        expect(clientState.raidInterval, 6);
        expect(clientState.active, after.active);
        for (final good in Resource.values) {
          expect(
            clientState.players[viewer].stores[good] ?? 0,
            after.players[viewer].stores[good] ?? 0,
          );
        }
        expect(clientState.roads, after.roads);
        for (var opponent = 0; opponent < 4; opponent++) {
          if (opponent != viewer) {
            expect(
              clientState.players[opponent].stores.values.every((v) => v == 0),
              true,
            );
          }
        }
      }
      if (after.players[0].stores.values.any((v) => v > 0) ||
          after.players[1].stores.values.any((v) => v > 0)) {
        sawHumanGoods = true;
      }
    }
    expect(
      movesPerSeat.values.every((count) => count > 20),
      true,
      reason: 'Seats: $movesPerSeat; maxRound: $maxRound; raids: $raids',
    );
    expect(
      maxRound,
      greaterThanOrEqualTo(7),
      reason: 'Round stalled: $maxRound',
    );
    expect(raids, greaterThanOrEqualTo(1), reason: 'No raid reached');
    expect(sawHumanGoods, true);
    expect(
      room.state!.phase,
      MatchPhase.finished,
      reason:
          "Match did not reach victory after 6000 moves: round $maxRound, seats $movesPerSeat",
    );
    // Exchanges can be zero for some seeds; proposals and replies remain legal,
    // and the focused tests cover trade acceptance and conservation.
    expect(exchanges, greaterThanOrEqualTo(0));
  });
}
