import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_host.dart';
import 'package:stone_and_banner/network/room_protocol.dart';

void main() {
  test(
    'shuffled turn order drives setup, turns, replay and public snapshots',
    () {
      var state = MatchEngine.newGame(
        ['Host', 'Guest', 'Mira'],
        451,
        turnOrder: [2, 0, 1],
      );
      expect(state.active, 2);
      expect(state.turnOrder, [2, 0, 1]);
      var safety = 0;
      while (state.phase == MatchPhase.setupVillage ||
          state.phase == MatchPhase.setupRoad) {
        expect(safety++, lessThan(32));
        final event = MatchEngine.idleEvent(state);
        expect(event, isNotNull);
        state = MatchEngine.apply(state, event!);
      }
      expect(state.phase, MatchPhase.roll);
      expect(state.active, 2);
      expect(RoomProtocol.readView(RoomProtocol.view(state, 0)).turnOrder, [
        2,
        0,
        1,
      ]);
      for (final nextSeat in [0, 1, 2]) {
        safety = 0;
        while (state.phase != MatchPhase.actions) {
          expect(safety++, lessThan(35));
          state = MatchEngine.apply(state, MatchEngine.idleEvent(state)!);
        }
        state = MatchEngine.apply(state, const EndTurn());
        expect(state.active, nextSeat);
        final restored = MatchEngine.importReplay(
          MatchEngine.exportReplay(state),
        );
        expect(restored.turnOrder, [2, 0, 1]);
        expect(restored.active, nextSeat);
        expect(restored.round, state.round);
      }
      expect(state.round, 2);
    },
  );

  test('room preserves human seat IDs while shuffling gameplay order', () {
    final room = HostedRoom('ABCD', 3, 123, shuffleTurns: true);
    for (final name in ['Host', 'Guest', 'Mira']) {
      room.join(name);
    }
    room.start(0);
    expect(room.seats.map((s) => s.name).toList(), ['Host', 'Guest', 'Mira']);
    expect(room.state!.turnOrder.toSet(), {0, 1, 2});
    expect(room.state!.active, room.state!.turnOrder.first);
    expect(
      MatchEngine.importReplay(room.privateReplay()).turnOrder,
      room.state!.turnOrder,
    );
  });

  test(
    'bandit AI attacks the leading opponent rather than weaker neighbours',
    () {
      final initial = MatchEngine.newGame(['Bot', 'Leader', 'Trailer'], 891);
      final tiles = initial.board.tiles;
      final topology = initial.topology;
      final first = List.generate(
        tiles.length,
        (i) => i,
      ).firstWhere((i) => i != initial.banditTile);
      final vLeader = topology.tileVertices[first].first;
      final second = List.generate(tiles.length, (i) => i).firstWhere(
        (i) =>
            i != first &&
            i != initial.banditTile &&
            topology.tileVertices[i]
                .toSet()
                .intersection(topology.tileVertices[first].toSet())
                .isEmpty,
      );
      final vTrailer = topology.tileVertices[second].first;
      final players = initial.players.toList();
      players[1] = players[1].copyWith(
        charterPoints: 7,
        stores: {Resource.wood: 4},
      );
      players[2] = players[2].copyWith(stores: {Resource.wood: 4});
      final state = initial.copyWith(
        phase: MatchPhase.bandit,
        active: 0,
        players: players,
        builders: {1, 2},
        sites: {
          vLeader: const Site(1, Structure.village),
          vTrailer: const Site(2, Structure.town),
        },
      );
      final choice = const HeuristicAi().choose(state);
      expect(choice, isA<MoveBandit>());
      expect((choice as MoveBandit).victim, 1);
    },
  );
}
