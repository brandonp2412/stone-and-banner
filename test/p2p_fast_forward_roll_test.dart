import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/p2p_room.dart';

void main() {
  test('host fast-forward ends with exactly one human roll', () async {
    final room = P2pRoom(botMoveDelay: const Duration(seconds: 2));
    addTearDown(room.dispose);
    room.host('Host', 3, 4613);
    room.setBotCount(2);
    room.start();
    room.replaceHostStateForTest((initial) {
      var s = initial;
      for (var i = 0; i < 6; i++) {
        s = MatchEngine.apply(
          s,
          PlaceVillage(MatchEngine.legalVertices(s).first),
        );
        s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
      }
      return s.copyWith(active: 2, phase: MatchPhase.actions);
    });
    final before = room.authoritativeStateForTest!.events.length;
    room.fastForwardBots();
    for (var i = 0; i < 200; i++) {
      final s = room.authoritativeStateForTest!;
      if (s.active == 0 && s.phase != MatchPhase.roll) break;
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    final after = room.authoritativeStateForTest!;
    expect(after.active, 0);
    expect(after.phase, isNot(MatchPhase.roll));
    expect(after.events.skip(before).whereType<RollDice>(), hasLength(1));
  });
}
