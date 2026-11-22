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

/// A port's anchor and its measured text size. The whole set is laid out
/// together so neighbouring badges cannot overlap or get covered by a leader.
class DockLabelRequest {
  const DockLabelRequest(this.edgeMidpoint, this.labelSize);
  final Offset edgeMidpoint;
  final Size labelSize;
}

/// Uses the *side* gutters on landscape boards. Unlike positioning badges one
/// at a time, this packs neighbouring port labels without hiding any text.
List<Offset> layoutDockLabels({
  required Size size,
  required Rect boardBounds,
  required double radius,
  required List<DockLabelRequest> requests,
}) {
  if (requests.isEmpty) return const [];
  final widestBadge = requests
      .map((request) => request.labelSize.width + 12)
      .reduce(math.max);
  final hasSideGutters =
      size.width > size.height * 1.25 &&
      boardBounds.left >= widestBadge + 26 &&
      size.width - boardBounds.right >= widestBadge + 26;
  if (!hasSideGutters && size.width > size.height * 1.25) {
    // On narrower desktop windows the board nearly touches both sides.
    // Place the ports in the reserved top/bottom strips instead of putting
    // side labels over playable hexes.
    final positions = List<Offset>.filled(requests.length, Offset.zero);
    for (final isTop in [true, false]) {
      final indices =
          [
            for (var i = 0; i < requests.length; i++)
              if ((requests[i].edgeMidpoint.dy < size.height / 2) == isTop) i,
          ]..sort(
            (a, b) => requests[a].edgeMidpoint.dx.compareTo(
              requests[b].edgeMidpoint.dx,
            ),
          );
      if (indices.isEmpty) continue;
      final topHudClearance = isTop ? math.min(155.0, size.width * .23) : 5.0;
      final rightBound = size.width - 5;
      final sumWidths = indices.fold<double>(
        0,
        (sum, index) => sum + requests[index].labelSize.width + 12,
      );
      final gap = indices.length > 1
          ? math.min(
              8.0,
              math.max(
                0,
                (rightBound - topHudClearance - sumWidths) /
                    (indices.length - 1),
              ),
            )
          : 0.0;
      final xs = <double>[];
      var nextLeft = topHudClearance;
      for (final index in indices) {
        final width = requests[index].labelSize.width + 12;
        final desiredLeft = requests[index].edgeMidpoint.dx - width / 2;
        final left = math.max(nextLeft, desiredLeft);
        xs.add(left + width / 2);
        nextLeft = left + width + gap;
      }
      if (nextLeft - gap > rightBound) {
        var maxRight = rightBound;
        for (var n = indices.length - 1; n >= 0; n--) {
          final width = requests[indices[n]].labelSize.width + 12;
          xs[n] = math.min(xs[n], maxRight - width / 2);
          maxRight = xs[n] - width / 2 - gap;
        }
      }
      for (var n = 0; n < indices.length; n++) {
        final index = indices[n];
        final height = requests[index].labelSize.height + 8;
        positions[index] = Offset(
          xs[n],
          isTop
              ? math.max(height / 2 + 2, boardBounds.top - height / 2 - 6)
              : math.min(
                  size.height - height / 2 - 2,
                  boardBounds.bottom + height / 2 + 6,
                ),
        );
      }
    }
    return positions;
  }
  if (!hasSideGutters) {
    return [
      for (final request in requests)
        dockLabelPosition(
          size: size,
          edgeMidpoint: request.edgeMidpoint,
          boardBounds: boardBounds,
          labelSize: request.labelSize,
          radius: radius,
        ),
    ];
  }

  final positions = List<Offset>.filled(requests.length, Offset.zero);
  for (final isLeft in [true, false]) {
    final indices =
        [
          for (var i = 0; i < requests.length; i++)
            if ((requests[i].edgeMidpoint.dx < size.width / 2) == isLeft) i,
        ]..sort(
          (a, b) => requests[a].edgeMidpoint.dy.compareTo(
            requests[b].edgeMidpoint.dy,
          ),
        );
    if (indices.isEmpty) continue;

    // On especially short phone screens, a fifth label cannot fit between
    // the raid HUD and the bottom Actions button. Place its northernmost port
    // in the otherwise empty top gutter, clear of the HUD and terrain.
    if (isLeft && size.height < 260 && indices.length > 4) {
      final first = indices.removeAt(0);
      final labelSize = requests[first].labelSize;
      positions[first] = Offset(
        boardBounds.left + 8 + labelSize.width / 2 + 6,
        boardBounds.top - (labelSize.height + 8) / 2 - 5,
      );
    }

    // The top-left raid panel and bottom action controls need breathing room.
    final top = math.min(84.0, size.height * .28);
    final bottom = math.max(
      top + 12,
      size.height - (size.height < 260 ? 66 : 70),
    );
    final totalBadgeHeight = indices.fold<double>(
      0,
      (sum, index) => sum + requests[index].labelSize.height + 8,
    );
    final gap = indices.length > 1
        ? math.min(
            8.0,
            math.max(
              0,
              (bottom - top - totalBadgeHeight) / (indices.length - 1),
            ),
          )
        : 0.0;
    final ys = <double>[];
    var nextTop = top;
    for (final index in indices) {
      final height = requests[index].labelSize.height + 8;
      final wanted = requests[index].edgeMidpoint.dy - height / 2;
      final placed = math.max(nextTop, wanted);
      ys.add(placed + height / 2);
      nextTop = placed + height + gap;
    }
    // Shift upward if the last port would otherwise descend into the tray.
    if (nextTop - gap > bottom) {
      var maxBottom = bottom;
      for (var n = indices.length - 1; n >= 0; n--) {
        final height = requests[indices[n]].labelSize.height + 8;
        ys[n] = math.min(ys[n], maxBottom - height / 2);
        maxBottom = ys[n] - height / 2 - gap;
      }
    }
    for (var n = 0; n < indices.length; n++) {
      final index = indices[n];
      final width = requests[index].labelSize.width + 12;
      positions[index] = Offset(
        isLeft
            ? boardBounds.left - 14 - width / 2
            : boardBounds.right + 14 + width / 2,
        ys[n],
      );
    }
  }
  return positions;
}
