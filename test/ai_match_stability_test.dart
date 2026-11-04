import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';

/// Finds a simple road trail without using prohibited vertices. This fixture
/// constructs topology directly, then tests actual reducer tie recalculation.
List<int> _trail(
  BoardTopology topology,
  int length, {
  Set<int> excludedVertices = const {},
}) {
  List<int>? walk(int vertex, List<int> path, Set<int> visited) {
    if (path.length == length) return path;
    for (final edgeId in topology.vertices[vertex].edges) {
      final edge = topology.edges[edgeId];
      final other = edge.a == vertex ? edge.b : edge.a;
      if (visited.contains(other) || excludedVertices.contains(other)) {
        continue;
      }
      final result = walk(other, [...path, edgeId], {...visited, other});
      if (result != null) return result;
    }
    return null;
  }

  for (final start in topology.vertices) {
    if (excludedVertices.contains(start.id)) continue;
    final found = walk(start.id, [], {start.id});
    if (found != null) return found;
  }
  throw StateError('No disjoint simple trail of $length edges');
}

Set<int> _vertices(BoardTopology topology, List<int> edges) => {
  for (final id in edges) ...[topology.edges[id].a, topology.edges[id].b],
};

void main() {
  test('five-road tie retains incumbent; no incumbent remains unawarded', () {
    final initial = MatchEngine.newGame(['A', 'B', 'C'], 818);
    final topology = initial.topology;
    final first = _trail(topology, 5);
    final second = _trail(
      topology,
      6,
      excludedVertices: _vertices(topology, first),
    );
    final roads = <int, int>{
      for (final e in first) e: 0,
      for (final e in second.take(4)) e: 1,
    };
    final people = initial.players.toList();
    people[1] = people[1].copyWith(
      stores: {Resource.wood: 2, Resource.brick: 2},
    );
    final before = initial.copyWith(
      phase: MatchPhase.actions,
      active: 1,
      roads: roads,
      players: people,
      bank: {...initial.bank, Resource.wood: 17, Resource.brick: 17},
      longestRoadHolder: 0,
    );
    expect(MatchEngine.longestRoad(before, 0), 5);
    expect(MatchEngine.longestRoad(before, 1), 4);
    expect(MatchEngine.legalRoad(before, second[4]), isTrue);

    final tied = MatchEngine.apply(before, PlaceRoad(second[4]));
    expect(MatchEngine.longestRoad(tied, 1), 5);
    expect(tied.longestRoadHolder, 0);
    expect(MatchEngine.score(tied, 0), 2);
    expect(MatchEngine.score(tied, 1), 0);

    final neutral = before.copyWith(clearRoadHolder: true);
    final unawardedTie = MatchEngine.apply(neutral, PlaceRoad(second[4]));
    expect(unawardedTie.longestRoadHolder, isNull);

    expect(MatchEngine.legalRoad(tied, second[5]), isTrue);
    final overtaken = MatchEngine.apply(tied, PlaceRoad(second[5]));
    expect(MatchEngine.longestRoad(overtaken, 1), 6);
    expect(overtaken.longestRoadHolder, 1);
    expect(MatchEngine.score(overtaken, 0), 0);
    expect(MatchEngine.score(overtaken, 1), 2);
  });

  test('fifteen points is the only victory threshold', () {
    final initial = MatchEngine.newGame(['A', 'B', 'C', 'D'], 819);
    // A synthetic score fixture checks winner threshold independently of AI
    // move selection. Full replay-based victories are sampled by the corpus.
    final players = initial.players.toList();
    players[0] = players[0].copyWith(charterPoints: 14);
    final fourteen = initial.copyWith(players: players);
    expect(MatchEngine.winner(fourteen), isNull);
    players[0] = players[0].copyWith(charterPoints: 15);
    final fifteen = initial.copyWith(players: players);
    expect(MatchEngine.winner(fifteen), 0);
  });
}
