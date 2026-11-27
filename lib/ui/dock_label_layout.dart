import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// A port badge is attached to its own shore by a short, perpendicular stem.
/// The map never shrinks to accommodate labels. At the viewport boundary
/// the badge can hug the shore rather than being clipped.
({Rect badge, Offset shore, Offset connection}) coastalDockBadge({
  required Size size,
  required Offset a,
  required Offset b,
  required Offset tileCenter,
  required bool hasResource,
}) {
  final shore = (a + b) / 2;
  final edge = b - a;
  var normal = Offset(-edge.dy, edge.dx) / edge.distance;
  final towardTile = tileCenter - shore;
  if (normal.dx * towardTile.dx + normal.dy * towardTile.dy > 0) {
    normal = -normal;
  }
  const width = 42.0;
  const height = 20.0;
  final support = normal.dx.abs() * width / 2 + normal.dy.abs() * height / 2;
  final preferred = shore + normal * (support + 6);
  // Preserve the original board projection. Move only a badge that would
  // leave the canvas, keeping the adjustment as small as possible.
  var center = Offset(
    preferred.dx.clamp(
      width / 2 + 2,
      math.max(width / 2 + 2, size.width - width / 2 - 2),
    ),
    preferred.dy.clamp(
      height / 2 + 2,
      math.max(height / 2 + 2, size.height - height / 2 - 2),
    ),
  );
  // The raid HUD is pinned to the top-left on landscape layouts. A port
  // next to it can slide along its own vertical shore, rather than hiding.
  final raidHud = const Rect.fromLTWH(10, 8, 145, 60);
  if (size.width > 550 &&
      size.aspectRatio < 2.2 &&
      Rect.fromCenter(
        center: center,
        width: width,
        height: height,
      ).overlaps(raidHud)) {
    center = Offset(center.dx, raidHud.bottom + height / 2 + 3);
  }
  final badge = Rect.fromCenter(center: center, width: width, height: height);
  final connection = Offset(
    shore.dx.clamp(badge.left, badge.right),
    shore.dy.clamp(badge.top, badge.bottom),
  );
  return (badge: badge, shore: shore, connection: connection);
}
