import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/dock_label_layout.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  test('wide boards use more space than the original projection', () {
    final landscape = BoardGeometry(const Size(780, 250));
    expect(
      landscape.radius * landscape.horizontalFactor,
      greaterThan(
        220 /
            (8 * BoardGeometry.verticalScale) *
            BoardGeometry.horizontalScale *
            1.12,
      ),
    );
    expect(BoardGeometry(const Size(360, 630)).radius, greaterThan(360 / 9.6));
  });

  test('every port badge is local, visible and distinct at full map scale', () {
    final state = tableWithSupplies();
    for (final size in [
      const Size(580, 220),
      const Size(640, 220),
      const Size(780, 250),
      const Size(844, 290),
      const Size(1024, 550),
      const Size(1536, 508),
      const Size(360, 630),
      const Size(393, 695),
    ]) {
      final g = BoardGeometry(size);
      final badges = <Rect>[];
      for (final dock in state.topology.docks) {
        final a = g.vertex(state.topology.vertices[dock.edge.a]);
        final b = g.vertex(state.topology.vertices[dock.edge.b]);
        final tile = g.tile(state.board.tiles[dock.edge.tiles.single].position);
        final port = coastalDockBadge(
          size: size,
          a: a,
          b: b,
          tileCenter: tile,
          hasResource: dock.resource != null,
        );
        final badge = port.badge;
        expect(
          badge.left,
          greaterThanOrEqualTo(0),
          reason: '$size ${dock.label}',
        );
        expect(
          badge.top,
          greaterThanOrEqualTo(0),
          reason: '$size ${dock.label}',
        );
        expect(
          badge.right,
          lessThanOrEqualTo(size.width),
          reason: '$size ${dock.label}',
        );
        expect(
          badge.bottom,
          lessThanOrEqualTo(size.height),
          reason: '$size ${dock.label}',
        );
        expect((port.connection - port.shore).distance, lessThan(20));
        final edge = b - a;
        double cross(Offset point) =>
            edge.dx * (point.dy - a.dy) - edge.dy * (point.dx - a.dx);
        // On a tight viewport the badge can touch the coastal edge, but
        // its center must stay on the water side and close to that port.
        expect(cross(badge.center) * cross(tile), lessThan(0));
        expect((badge.center - port.shore).distance, lessThan(35));
        for (final previous in badges) {
          expect(
            badge.overlaps(previous),
            isFalse,
            reason: '$size ${dock.label}',
          );
        }
        badges.add(badge);
      }
      expect(badges, hasLength(9));
    }
  });
}
