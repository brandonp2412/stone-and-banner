import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/dock_label_layout.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  test('short portrait badge fits beside the coast near the canvas edge', () {
    const edge = Offset(44, 331);
    final label = layoutDockLabels(
      size: const Size(435, 730),
      boardBounds: const Rect.fromLTRB(24, 185, 414, 545),
      radius: 45,
      boardVertices: const [
        Offset(24, 342),
        Offset(141, 185),
        Offset(297, 185),
        Offset(414, 342),
        Offset(297, 545),
        Offset(141, 545),
      ],
      requests: const [DockLabelRequest(edge, Size(22, 16))],
    ).single;
    expect((label - edge).distance, lessThan(65));
    expect(label.dx, lessThan(edge.dx));
    expect(label.dy, lessThan(edge.dy));
  });

  test('labels use open water beside angled coasts when they fit', () {
    const size = Size(800, 600);
    const bounds = Rect.fromLTRB(200, 100, 600, 500);
    const edge = Offset(300, 200);
    const requests = [DockLabelRequest(edge, Size(62, 16))];
    final previous = layoutDockLabels(
      size: size,
      boardBounds: bounds,
      radius: 60,
      requests: requests,
    ).single;
    final close = layoutDockLabels(
      size: size,
      boardBounds: bounds,
      radius: 60,
      requests: requests,
      boardVertices: const [
        Offset(400, 100),
        Offset(600, 300),
        Offset(400, 500),
        Offset(200, 300),
      ],
    ).single;
    expect((close - edge).distance, lessThan((previous - edge).distance));
    final badge = Rect.fromCenter(center: close, width: 74, height: 24);
    // The northwest coast has x + y = 500; the badge stays in water.
    expect(badge.right + badge.bottom, lessThan(500));
    expect((Offset.zero & size).contains(badge.topLeft), isTrue);
    expect((Offset.zero & size).contains(badge.bottomRight), isTrue);
  });

  test('north and south dock labels clear board in landscape layouts', () {
    final topology = tableWithSupplies().topology;
    for (final size in [
      const Size(640, 320),
      const Size(640, 220),
      const Size(844, 280),
      const Size(844, 290),
      const Size(580, 300),
      const Size(580, 250),
      const Size(580, 275),
      const Size(575, 260),
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
      const Size(580, 300),
      const Size(580, 250),
      const Size(580, 275),
      const Size(575, 260),
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

  test('wide glyphs do not stack over other port badges', () {
    final topology = tableWithSupplies().topology;
    for (final size in [
      const Size(580, 260),
      const Size(580, 300),
      const Size(640, 220),
      const Size(844, 290),
      const Size(1536, 508),
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
            Size(dock.label.length * 12, 16),
          ),
      ];
      final centers = layoutDockLabels(
        size: size,
        boardBounds: boardBounds,
        radius: geometry.radius,
        requests: requests,
      );
      final badges = [
        for (var i = 0; i < centers.length; i++)
          Rect.fromCenter(
            center: centers[i],
            width: requests[i].labelSize.width + 12,
            height: requests[i].labelSize.height + 8,
          ),
      ];
      for (var i = 0; i < badges.length; i++) {
        for (var j = i + 1; j < badges.length; j++) {
          expect(
            badges[i].overlaps(badges[j]),
            isFalse,
            reason: 'Dock $i overlaps $j at $size',
          );
        }
      }
    }
  });

  test('portrait board uses available height for a larger top-down table', () {
    final landscape = BoardGeometry(const Size(900, 500));
    for (final size in [const Size(360, 630), const Size(393, 695)]) {
      final geometry = BoardGeometry(size);
      expect(geometry.horizontalFactor, 1);
      expect(geometry.verticalFactor, 1);
      final previousRadius = math.min(
        size.width / (9.6 * landscape.horizontalFactor),
        (size.height - 112) / (8 * landscape.verticalFactor),
      );
      expect(geometry.radius, greaterThan(previousRadius));
    }
  });

  test('landscape board reclaims the vertical dock-label gutter', () {
    const size = Size(1536, 508);
    final previousRadius =
        (size.height - 64) / (8 * BoardGeometry.verticalScale);
    expect(BoardGeometry(size).radius, greaterThan(previousRadius));
  });
}
