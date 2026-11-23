import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

Future<void> tapBoardTarget(
  WidgetTester tester,
  MatchState state, {
  int? vertex,
  int? edge,
}) async {
  final map = find.byKey(const ValueKey('realm-map'));
  final geometry = BoardGeometry(tester.getSize(map));
  final Offset point;
  if (edge != null || state.phase == MatchPhase.setupRoad) {
    final road =
        state.topology.edges[edge ?? MatchEngine.legalEdges(state).first];
    point =
        (geometry.vertex(state.topology.vertices[road.a]) +
            geometry.vertex(state.topology.vertices[road.b])) /
        2;
  } else {
    point = geometry.vertex(
      state.topology.vertices[vertex ?? MatchEngine.legalVertices(state).first],
    );
  }
  await tester.tapAt(tester.getTopLeft(map) + point);
  await tester.pumpAndSettle();
}
