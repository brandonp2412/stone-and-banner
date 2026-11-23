import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/dock_label_layout.dart';
import 'package:stone_and_banner/ui/dock_leader_paths.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  test('shore labels keep their connecting lines out of the hex terrain', () {
    final state = tableWithSupplies();
    for (final size in [
      const Size(780, 258), // Samsung S25 landscape, below the standings.
      const Size(360, 630), // Samsung portrait, below standings and tray.
      const Size(393, 695),
      const Size(640, 214),
      const Size(844, 290),
      const Size(1024, 550),
      const Size(1536, 508),
    ]) {
      final geometry = BoardGeometry(size);
      final vertices = state.topology.vertices.map(geometry.vertex).toList();
      final board = Rect.fromLTRB(
        vertices.map((p) => p.dx).reduce(math.min),
        vertices.map((p) => p.dy).reduce(math.min),
        vertices.map((p) => p.dx).reduce(math.max),
        vertices.map((p) => p.dy).reduce(math.max),
      );
      final requests = [
        for (final dock in state.topology.docks)
          DockLabelRequest(
            (geometry.vertex(state.topology.vertices[dock.edge.a]) +
                    geometry.vertex(state.topology.vertices[dock.edge.b])) /
                2,
            Size(dock.label.length * 7.2, 16),
          ),
      ];
      final labels = layoutDockLabels(
        boardVertices: vertices,
        size: size,
        boardBounds: board,
        radius: geometry.radius,
        requests: requests,
      );
      final paths = layoutDockLeaderPaths(
        size: size,
        tileCenters: [
          for (final tile in state.board.tiles) geometry.tile(tile.position),
        ],
        radius: geometry.radius,
        horizontalFactor: geometry.horizontalFactor,
        verticalFactor: geometry.verticalFactor,
        requests: [
          for (var i = 0; i < requests.length; i++)
            DockLeaderRequest(
              shore: requests[i].edgeMidpoint,
              badge: Rect.fromCenter(
                center: labels[i],
                width: requests[i].labelSize.width + 12,
                height: requests[i].labelSize.height + 8,
              ),
            ),
        ],
      );
      expect(paths, hasLength(requests.length));
      for (var port = 0; port < paths.length; port++) {
        final points = paths[port];
        expect(points.length, greaterThan(1), reason: '$size port $port');
        expect(points.first, requests[port].edgeMidpoint);
        expect(
          (points.last - labels[port]).distance,
          lessThan(requests[port].labelSize.width),
          reason: '$size port $port must terminate at badge',
        );
        for (var i = 0; i < points.length - 1; i++) {
          final a = points[i], b = points[i + 1];
          final length = (b - a).distance;
          for (var step = 0; step <= length; step += 2) {
            if (i == 0 && step < 4) continue;
            final p = a + (b - a) * (step / math.max(1, length));
            expect(
              p.dx,
              inInclusiveRange(0, size.width),
              reason: '$size port $port out of canvas at $p',
            );
            expect(
              p.dy,
              inInclusiveRange(0, size.height),
              reason: '$size port $port out of canvas at $p',
            );
            for (final tile in state.board.tiles) {
              final center = geometry.tile(tile.position);
              final x =
                  (p.dx - center.dx).abs() /
                  (geometry.radius * geometry.horizontalFactor);
              final y =
                  (p.dy - center.dy).abs() /
                  (geometry.radius * geometry.verticalFactor);
              expect(
                x < math.sqrt(3) / 2 && y < 1 - x / math.sqrt(3),
                isFalse,
                reason: '$size port $port leader crosses terrain at $p',
              );
            }
          }
        }
      }
    }
  });
}
