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

  // Coastal edges on the north/south arcs need more separation than the
  // ordinary radial offset: their text must clear the *entire* land outline.
  if (outward.dy.abs() >= outward.dx.abs() * .55) {
    if (outward.dy < 0) {
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
