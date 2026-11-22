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
      const Size(640, 220),
      const Size(844, 280),
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

  test('all landscape port badges remain distinct and clear of terrain', () {
    final topology = tableWithSupplies().topology;
    for (final size in [
      const Size(640, 220),
      const Size(844, 280),
      const Size(844, 290),
      const Size(1024, 550),
      const Size(1536, 508),
      const Size(1530, 800),
    ]) {
      final geometry = BoardGeometry(size);
      final vertices = topology.vertices.map(geometry.vertex).toList();
      final boardBounds = Rect.fromLTRB(
        vertices.map((p) => p.dx).reduce(math.min),
        vertices.map((p) => p.dy).reduce(math.min),
        vertices.map((p) => p.dx).reduce(math.max),
        vertices.map((p) => p.dy).reduce(math.max),
      );
      final requests = [
        for (final dock in topology.docks)
          DockLabelRequest(
            (geometry.vertex(topology.vertices[dock.edge.a]) +
                    geometry.vertex(topology.vertices[dock.edge.b])) /
                2,
            Size(dock.label.length * 7.2, 16),
          ),
      ];
      final labels = layoutDockLabels(
        size: size,
        boardBounds: boardBounds,
        radius: geometry.radius,
        requests: requests,
      );
      expect(labels, hasLength(topology.docks.length));
      final badges = [
        for (var i = 0; i < labels.length; i++)
          Rect.fromCenter(
            center: labels[i],
            width: requests[i].labelSize.width + 12,
            height: requests[i].labelSize.height + 8,
          ),
      ];
      for (var i = 0; i < badges.length; i++) {
        final badge = badges[i];
        expect(badge.left, greaterThanOrEqualTo(0), reason: '$size $i');
        expect(badge.top, greaterThanOrEqualTo(0), reason: '$size $i');
        expect(badge.right, lessThanOrEqualTo(size.width), reason: '$size $i');
        expect(
          badge.bottom,
          lessThanOrEqualTo(size.height),
          reason: '$size $i',
        );
        expect(
          badge.overlaps(boardBounds),
          isFalse,
          reason: 'Dock $i covers board at $size',
        );
        // In the compact fullscreen view, the raid HUD sits at top-left
        // while Actions / End Turn occupy the two bottom corners.
        if (size.height <= 290) {
          expect(
            badge.overlaps(const Rect.fromLTWH(10, 8, 135, 48)),
            isFalse,
            reason: 'Dock $i obscures raid HUD at $size',
          );
          expect(
            badge.overlaps(Rect.fromLTWH(10, size.height - 52, 130, 44)),
            isFalse,
            reason: 'Dock $i obscures Actions at $size',
          );
          expect(
            badge.overlaps(
              Rect.fromLTWH(size.width - 140, size.height - 52, 130, 44),
            ),
            isFalse,
            reason: 'Dock $i obscures End Turn at $size',
          );
        }
        for (var j = i + 1; j < badges.length; j++) {
          expect(
            badge.overlaps(badges[j]),
            isFalse,
            reason: 'Dock $i covers dock $j at $size',
          );
        }
      }
    }
  });

  test('landscape board reclaims the vertical dock-label gutter', () {
    const size = Size(1536, 508);
    final previousRadius =
        (size.height - 64) / (8 * BoardGeometry.verticalScale);
    expect(BoardGeometry(size).radius, greaterThan(previousRadius));
  });
}
