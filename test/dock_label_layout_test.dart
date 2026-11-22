import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/dock_label_layout.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  test('north and south dock labels clear board in landscape layouts', () {
    final topology = tableWithSupplies().topology;
    for (final size in [
      const Size(640, 320),
      const Size(844, 290),
      const Size(1024, 550),
      const Size(1530, 800),
    ]) {
      final g = BoardGeometry(size);
      final points = topology.vertices.map(g.vertex).toList();
      final boardBounds = Rect.fromLTRB(
        points.map((p) => p.dx).reduce(math.min),
        points.map((p) => p.dy).reduce(math.min),
        points.map((p) => p.dx).reduce(math.max),
        points.map((p) => p.dy).reduce(math.max),
      );
      var verticalLabels = 0;
      for (final dock in topology.docks) {
        final a = g.vertex(topology.vertices[dock.edge.a]);
        final b = g.vertex(topology.vertices[dock.edge.b]);
        final midpoint = (a + b) / 2;
        final outward = midpoint - g.center;
        const labelSize = Size(62, 16);
        final label = dockLabelPosition(
          size: size,
          edgeMidpoint: midpoint,
          boardBounds: boardBounds,
          labelSize: labelSize,
          radius: g.radius,
        );
        final rect = Rect.fromCenter(
          center: label,
          width: labelSize.width,
          height: labelSize.height,
        );
        expect(
          Rect.fromLTWH(0, 0, size.width, size.height).contains(rect.topLeft),
          isTrue,
        );
        expect(rect.right <= size.width && rect.bottom <= size.height, isTrue);
        if (outward.dy.abs() >= outward.dx.abs() * .55) {
          verticalLabels++;
          if (size.width > size.height * 1.25 &&
              boardBounds.left > labelSize.width + 24 &&
              size.width - boardBounds.right > labelSize.width + 24) {
            expect(
              rect.right < boardBounds.left || rect.left > boardBounds.right,
              isTrue,
              reason: 'Top/bottom dock must use a side gutter at $size',
            );
            expect(
              rect.top,
              greaterThan(60),
              reason: 'Dock must not obscure the raid HUD at $size',
            );
          } else if (outward.dy < 0) {
            expect(rect.bottom, lessThan(boardBounds.top));
          } else {
            expect(rect.top, greaterThan(boardBounds.bottom));
          }
        }
      }
      expect(verticalLabels, greaterThan(0));
    }
  });
}
