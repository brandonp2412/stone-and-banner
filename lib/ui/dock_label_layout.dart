import 'dart:math' as math;

import 'package:flutter/painting.dart';

// A board's ports do not move during animation frames. Cache the layout to
// avoid re-running collision packing every time the board repaints.
final _dockLayoutCache = <String, List<Offset>>{};

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

/// Fit labels as close to their ports as possible. Only move a badge around a
/// corner when that coast has no spare room: the playable board keeps its full
/// horizontal and vertical extent regardless of where its ports are labelled.
List<Offset> layoutDockLabels({
  required Size size,
  required Rect boardBounds,
  required double radius,
  required List<DockLabelRequest> requests,
}) {
  if (requests.isEmpty) return const [];
  final signature = StringBuffer()
    ..write(
      '${size.width}/${size.height}/${boardBounds.left}/'
      '${boardBounds.top}/${boardBounds.right}/${boardBounds.bottom}/$radius',
    );
  for (final request in requests) {
    signature.write(
      '/${request.edgeMidpoint.dx}/${request.edgeMidpoint.dy}/'
      '${request.labelSize.width}/${request.labelSize.height}',
    );
  }
  final key = signature.toString();
  final cached = _dockLayoutCache[key];
  if (cached != null) return cached;

  List<Offset> cache(List<Offset> labels) {
    if (_dockLayoutCache.length >= 24) {
      _dockLayoutCache.remove(_dockLayoutCache.keys.first);
    }
    _dockLayoutCache[key] = labels;
    return labels;
  }

  const edgeGap = 6.0;
  const badgeGap = 4.0;
  final canvas = Offset.zero & size;
  final compact = size.width > size.height * 1.25;
  // Overlay coordinates are relative to the Board painter, not the entire
  // screen. The mobile Actions/turn buttons occupy the lower corners.
  final overlays = compact
      ? <Rect>[
          Rect.fromLTWH(6, 5, math.min(150, size.width * .24), 55),
          Rect.fromLTWH(8, size.height - 62, 143, 57),
          Rect.fromLTWH(size.width - 150, size.height - 62, 142, 57),
          if (size.height < 500) Rect.fromLTWH(size.width - 82, 65, 76, 100),
        ]
      : <Rect>[];

  Rect badge(int index, Offset center) => Rect.fromCenter(
    center: center,
    width: requests[index].labelSize.width + 12,
    height: requests[index].labelSize.height + 8,
  );

  bool clearStatic(int index, Offset center) {
    final rect = badge(index, center);
    // Keep badges away from both the playable terrain and HUD touch targets.
    if (!canvas.contains(rect.topLeft) ||
        !canvas.contains(rect.bottomRight) ||
        rect.overlaps(boardBounds.inflate(1))) {
      return false;
    }
    return !overlays.any((overlay) => rect.inflate(2).overlaps(overlay));
  }

  // Candidate badges remain adjacent to an actual coast, never in the terrain.
  // Sample short shifts first, but retain room to pack densely on small phones.
  List<Offset> candidates(int index) {
    final request = requests[index];
    final edge = request.edgeMidpoint;
    final halfW = (request.labelSize.width + 12) / 2;
    final halfH = (request.labelSize.height + 8) / 2;
    final left = boardBounds.left - halfW - edgeGap;
    final right = boardBounds.right + halfW + edgeGap;
    final top = boardBounds.top - halfH - edgeGap;
    final bottom = boardBounds.bottom + halfH + edgeGap;
    final positions = <Offset>[];
    void offer(Offset position) {
      if (clearStatic(index, position)) positions.add(position);
    }

    for (final x in [left, right]) {
      offer(Offset(x, edge.dy));
      for (var y = halfH; y <= size.height - halfH; y += 4) {
        offer(Offset(x, y));
      }
    }
    for (final y in [top, bottom]) {
      offer(Offset(edge.dx, y));
      for (var x = halfW; x <= size.width - halfW; x += 4) {
        offer(Offset(x, y));
      }
    }
    positions.sort(
      (a, b) =>
          (a - edge).distanceSquared.compareTo((b - edge).distanceSquared),
    );
    return positions;
  }

  final possibilities = [
    for (var i = 0; i < requests.length; i++) candidates(i),
  ];
  final order = List<int>.generate(requests.length, (i) => i)
    ..sort((a, b) {
      // Place the widest, most constrained badges first; small generic ports
      // can fill the remaining gaps around them.
      final count = possibilities[a].length.compareTo(possibilities[b].length);
      if (count != 0) return count;
      return requests[b].labelSize.width.compareTo(requests[a].labelSize.width);
    });

  // Beam search keeps several non-overlapping arrangements alive. Greedy
  // placement could strand a late label between two already placed badges,
  // even though moving an earlier badge a few pixels solves the whole row.
  List<Offset>? solve(int choices, int width) {
    var beam = <({List<Offset?> values, List<Rect> badges, double cost})>[
      (
        values: List<Offset?>.filled(requests.length, null),
        badges: <Rect>[],
        cost: 0.0,
      ),
    ];
    for (final index in order) {
      final next = <({List<Offset?> values, List<Rect> badges, double cost})>[];
      for (final state in beam) {
        var accepted = 0;
        for (final center in possibilities[index]) {
          final rect = badge(index, center).inflate(badgeGap / 2);
          if (state.badges.any(rect.overlaps)) continue;
          final values = List<Offset?>.of(state.values);
          values[index] = center;
          next.add((
            values: values,
            badges: [...state.badges, rect],
            cost: state.cost + (center - requests[index].edgeMidpoint).distance,
          ));
          if (++accepted >= choices) break;
        }
      }
      if (next.isEmpty) return null;
      next.sort((a, b) => a.cost.compareTo(b.cost));
      beam = next.take(width).toList();
    }
    return [for (final position in beam.first.values) position!];
  }

  for (final settings in [(16, 32), (40, 80), (100, 180)]) {
    final solution = solve(settings.$1, settings.$2);
    if (solution != null) return cache(solution);
  }
  // On compact maps several wide port names may compete for the same thin
  // strip. Try assigning them to other coasts and packing each strip as a
  // one-dimensional sequence; this prevents even very wide fonts overlapping.
  final sideOptions = <List<List<Offset>>>[];
  for (var i = 0; i < requests.length; i++) {
    final halfW = (requests[i].labelSize.width + 12) / 2;
    final halfH = (requests[i].labelSize.height + 8) / 2;
    final edgeX = [
      boardBounds.left - halfW - edgeGap,
      boardBounds.right + halfW + edgeGap,
    ];
    final edgeY = [
      boardBounds.top - halfH - edgeGap,
      boardBounds.bottom + halfH + edgeGap,
    ];
    sideOptions.add([
      for (var side = 0; side < 4; side++)
        [
          for (final point in possibilities[i])
            if (side < 2
                ? (point.dx - edgeX[side]).abs() < .01
                : (point.dy - edgeY[side - 2]).abs() < .01)
              point,
        ]..sort(
          (a, b) => side < 2 ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx),
        ),
    ]);
  }

  double coordinate(Offset point, int side) => side < 2 ? point.dy : point.dx;
  double halfLength(int i, int side) => side < 2
      ? (requests[i].labelSize.height + 8) / 2
      : (requests[i].labelSize.width + 12) / 2;

  List<(int, Offset)>? packSide(List<int> indices, int side) {
    if (indices.isEmpty) return [];
    indices.sort(
      (a, b) => coordinate(
        requests[a].edgeMidpoint,
        side,
      ).compareTo(coordinate(requests[b].edgeMidpoint, side)),
    );
    final candidates = [for (final i in indices) sideOptions[i][side]];
    if (candidates.any((c) => c.isEmpty)) return null;
    final costs = <List<double>>[];
    final previous = <List<int>>[];
    for (var row = 0; row < candidates.length; row++) {
      final rowCosts = <double>[];
      final rowPrevious = <int>[];
      var cheapest = double.infinity;
      var bestIndex = -1;
      var cursor = 0;
      for (final point in candidates[row]) {
        final position = coordinate(point, side);
        final start = position - halfLength(indices[row], side);
        if (row > 0) {
          final earlier = candidates[row - 1];
          while (cursor < earlier.length &&
              coordinate(earlier[cursor], side) +
                      halfLength(indices[row - 1], side) +
                      badgeGap <=
                  start) {
            if (costs[row - 1][cursor] < cheapest) {
              cheapest = costs[row - 1][cursor];
              bestIndex = cursor;
            }
            cursor++;
          }
        } else {
          cheapest = 0;
        }
        final distance = (point - requests[indices[row]].edgeMidpoint).distance;
        rowCosts.add(cheapest + distance);
        rowPrevious.add(bestIndex);
      }
      costs.add(rowCosts);
      previous.add(rowPrevious);
    }
    var last = -1;
    var minCost = double.infinity;
    for (var i = 0; i < costs.last.length; i++) {
      if (costs.last[i] < minCost) {
        minCost = costs.last[i];
        last = i;
      }
    }
    if (last < 0 || !minCost.isFinite) return null;
    final positions = <(int, Offset)>[];
    for (var row = indices.length - 1; row >= 0; row--) {
      positions.add((indices[row], candidates[row][last]));
      last = previous[row][last];
    }
    return positions;
  }

  final sideGroups = List.generate(4, (_) => <int>[]);
  final sideLengths = List.filled(4, 0.0);
  final choices = [
    for (var i = 0; i < requests.length; i++)
      [
        for (var side = 0; side < 4; side++)
          if (sideOptions[i][side].isNotEmpty)
            (
              side: side,
              distance:
                  (sideOptions[i][side].reduce(
                            (a, b) =>
                                (a - requests[i].edgeMidpoint)
                                        .distanceSquared <=
                                    (b - requests[i].edgeMidpoint)
                                        .distanceSquared
                                ? a
                                : b,
                          ) -
                          requests[i].edgeMidpoint)
                      .distance,
            ),
      ]..sort((a, b) => a.distance.compareTo(b.distance)),
  ];
  final byConstraint = List<int>.generate(requests.length, (i) => i)
    ..sort((a, b) {
      final choice = choices[a].length.compareTo(choices[b].length);
      if (choice != 0) return choice;
      return requests[b].labelSize.width.compareTo(requests[a].labelSize.width);
    });

  List<Offset>? packedResult;
  var attempts = 0;
  bool assign(int depth) {
    if (++attempts > 30000) return false;
    if (depth == byConstraint.length) {
      final resolved = List<Offset?>.filled(requests.length, null);
      for (var side = 0; side < 4; side++) {
        final fitted = packSide([...sideGroups[side]], side);
        if (fitted == null) return false;
        for (final (index, position) in fitted) {
          resolved[index] = position;
        }
      }
      final rects = [
        for (var i = 0; i < requests.length; i++)
          badge(i, resolved[i]!).inflate(badgeGap / 2),
      ];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          if (rects[i].overlaps(rects[j])) return false;
        }
      }
      packedResult = [for (final position in resolved) position!];
      return true;
    }
    final i = byConstraint[depth];
    for (final choice in choices[i]) {
      final side = choice.side;
      final length = halfLength(i, side) * 2;
      final occupied =
          sideLengths[side] +
          (sideGroups[side].isEmpty ? 0 : badgeGap) +
          length;
      final available = side < 2 ? size.height : size.width;
      if (occupied > available) continue;
      sideLengths[side] = occupied;
      sideGroups[side].add(i);
      if (assign(depth + 1)) return true;
      sideGroups[side].removeLast();
      sideLengths[side] -= (sideGroups[side].isEmpty ? 0 : badgeGap) + length;
    }
    return false;
  }

  if (assign(0)) return cache(packedResult!);

  // Extremes smaller than the available label perimeter are not solvable
  // without reducing map size; preserve the previous fallback in that case.
  return cache([
    for (var i = 0; i < requests.length; i++)
      possibilities[i].isNotEmpty
          ? possibilities[i].first
          : dockLabelPosition(
              size: size,
              edgeMidpoint: requests[i].edgeMidpoint,
              boardBounds: boardBounds,
              labelSize: requests[i].labelSize,
              radius: radius,
            ),
  ]);
}
