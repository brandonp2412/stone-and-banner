import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Positions coastal dock text outside the hex board with room for a leader.
/// All coordinates are in the painter's (unscaled) canvas space.
Offset dockLabelPosition({
  required Size size,
  required Offset edgeMidpoint,
  required Rect boardBounds,
  required Size labelSize,
  required double radius,
}) {
  final outward = edgeMidpoint - size.center(Offset.zero);
  final direction = outward.distance > 0
      ? outward / outward.distance
      : const Offset(0, -1);
  final projected = edgeMidpoint + direction * (radius * .65);
  final halfWidth = labelSize.width / 2;
  final halfHeight = labelSize.height / 2;
  const margin = 5.0;
  const clearance = 10.0;
  var x = projected.dx;
  var y = projected.dy;

  // In wide layouts place the north/south badges in the empty *corners*,
  // not in a row over/under the board. Their leader still points to the
  // original port, so all usable map height stays available to the hexes.
  final northOrSouth = outward.dy.abs() >= outward.dx.abs() * .55;
  if (northOrSouth) {
    if (size.width > size.height * 1.25 &&
        boardBounds.left > labelSize.width + 24 &&
        size.width - boardBounds.right > labelSize.width + 24) {
      // Keep labels beside (not above or below) the board and below the
      // top-left raid HUD. Pulling badges into the side gutters avoids
      // sacrificing vertical space from the playable terrain.
      x = outward.dx < 0
          ? boardBounds.left - halfWidth - clearance - 6
          : boardBounds.right + halfWidth + clearance + 6;
      y = edgeMidpoint.dy + (outward.dy < 0 ? radius * .65 : -radius * .65);
      y = y.clamp(
        math.min(size.height / 2, halfHeight + 70),
        math.max(size.height / 2, size.height - halfHeight - 43),
      );
    } else if (outward.dy < 0) {
      y = math.min(y, boardBounds.top - halfHeight - clearance);
    } else {
      y = math.max(y, boardBounds.bottom + halfHeight + clearance);
    }
  }
  return Offset(
    x.clamp(
      halfWidth + margin,
      math.max(halfWidth + margin, size.width - halfWidth - margin),
    ),
    y.clamp(
      halfHeight + margin,
      math.max(halfHeight + margin, size.height - halfHeight - margin),
    ),
  );
}
