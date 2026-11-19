import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';

import 'advanced_test.dart' show draft, fund;

void main() {
  test('setup pieces do not expose a player to theft; first build does', () {
    var s = draft(55).copyWith(active: 1, phase: MatchPhase.actions);
    final tile = List.generate(s.board.tiles.length, (i) => i).firstWhere(
      (tile) =>
          tile != s.banditTile &&
          s.topology.tileVertices[tile].any((v) => s.sites[v]?.owner == 1),
    );
    final protected = s.copyWith(active: 0, phase: MatchPhase.bandit);
    expect(MatchEngine.banditVictims(protected, tile), isNot(contains(1)));
    expect(
      () => MatchEngine.apply(protected, MoveBandit(tile, victim: 1)),
      throwsStateError,
    );
    expect(MatchEngine.apply(protected, MoveBandit(tile)).banditTile, tile);

    s = fund(s, 1, MatchEngine.effectiveRoadCost(s));
    s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
    expect(s.builders, contains(1));
    final exposed = s.copyWith(active: 0, phase: MatchPhase.bandit);
    expect(MatchEngine.banditVictims(exposed, tile), contains(1));
    expect(
      () => MatchEngine.apply(exposed, MoveBandit(tile)),
      throwsStateError,
    );
    final idle = MatchEngine.idleEvent(exposed) as MoveBandit;
    final idleVictims = MatchEngine.banditVictims(exposed, idle.tile);
    expect(idle.victim, idleVictims.isEmpty ? isNull : isIn(idleVictims));
    final before = exposed.players[1].stores.values.fold(0, (a, b) => a + b);
    final robbed = MatchEngine.apply(exposed, MoveBandit(tile, victim: 1));
    expect(
      robbed.players[1].stores.values.fold(0, (a, b) => a + b),
      before - 1,
    );

    // Losing that road later must not restore beginner protection.
    expect(
      MatchEngine.banditVictims(exposed.copyWith(roads: {}), tile),
      contains(1),
    );
  });
}
