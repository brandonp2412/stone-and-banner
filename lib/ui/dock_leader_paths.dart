import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The exact shore anchor and visible rectangular text badge of a port.
class DockLeaderRequest {
  const DockLeaderRequest({required this.shore, required this.badge});

  final Offset shore;
  final Rect badge;
}

// The port positions do not change during a match. In particular, avoid
// searching for paths for every frame of dice and road animations.
final _routeCache = <String, List<List<Offset>>>{};

/// Route port leaders in the water around the hexes, not diagonally across
/// land, villages and production numbers. The map is small enough to use
/// an outside-only visibility grid; the resulting path is simplified into a
/// handful of clean straight segments.
List<List<Offset>> layoutDockLeaderPaths({
  required Size size,
  required List<Offset> tileCenters,
  required double radius,
  double horizontalFactor = 1.28,
  double verticalFactor = .72,
  required List<DockLeaderRequest> requests,
}) {
  final signature = StringBuffer(
    '${size.width}/${size.height}/$radius/$horizontalFactor/$verticalFactor',
  );
  for (final tile in tileCenters) {
    signature.write('/${tile.dx},${tile.dy}');
  }
  for (final port in requests) {
    signature.write(
      '/${port.shore.dx},${port.shore.dy}/'
      '${port.badge.left},${port.badge.top},${port.badge.right},${port.badge.bottom}',
    );
  }
  final key = signature.toString();
  if (_routeCache[key] case final cached?) return cached;

  final step = math.min(size.width / 170, size.height / 64).clamp(3.0, 8.0);
  final columns = (size.width / step).ceil() + 1;
  final rows = (size.height / step).ceil() + 1;
  final count = columns * rows;
  final canvas = Offset.zero & size;
  final tileX = math.max(1, radius * horizontalFactor);
  final tileY = math.max(1, radius * verticalFactor);

  bool onTerrain(Offset point, double padding) {
    for (final center in tileCenters) {
      final x = (point.dx - center.dx).abs() / tileX;
      final y = (point.dy - center.dy).abs() / tileY;
      if (x <= math.sqrt(3) / 2 + padding / tileX &&
          y <= 1 - x / math.sqrt(3) + padding / tileY) {
        return true;
      }
    }
    return false;
  }

  final staticObstacles = <Rect>[
    Rect.fromLTWH(6, 5, math.min(150, size.width * .24), 55),
    Rect.fromLTWH(8, size.height - 62, 143, 57),
    Rect.fromLTWH(size.width - 150, size.height - 62, 142, 57),
    if (size.height < 500) Rect.fromLTWH(size.width - 82, 65, 76, 100),
  ];
  // On non-mobile boards the controls live elsewhere and these corners are
  // available for the shortest leader route.
  if (size.height >= 500) staticObstacles.clear();

  bool isClear(Offset point, List<Rect> obstacles, double padding) {
    if (!canvas.contains(point)) return false;
    if (onTerrain(point, padding)) return false;
    for (final rect in obstacles) {
      if (rect.inflate(padding).contains(point)) return false;
    }
    return true;
  }

  bool clearLine(
    Offset a,
    Offset b,
    List<Rect> obstacles, {
    bool startingAtShore = false,
  }) {
    final distance = (b - a).distance;
    final segments = math.max(1, (distance / 2).ceil());
    for (var i = 0; i <= segments; i++) {
      final travelled = distance * i / segments;
      // A dock is on the coastal edge. The first few pixels leave the shore,
      // so terrain clearance starts after the segment has departed the edge.
      if (startingAtShore && travelled < 4.0) continue;
      if (!isClear(a + (b - a) * (i / segments), obstacles, 1.3)) {
        return false;
      }
    }
    return true;
  }

  int index(int x, int y) => y * columns + x;
  Offset gridPoint(int i) =>
      Offset((i % columns) * step, (i ~/ columns) * step);
  int nearestFree(Offset position, List<bool> blocked) {
    final cx = (position.dx / step).round().clamp(0, columns - 1);
    final cy = (position.dy / step).round().clamp(0, rows - 1);
    var best = -1;
    var distance = double.infinity;
    for (var extent = 0; extent <= 7; extent++) {
      for (
        var y = math.max(0, cy - extent);
        y <= math.min(rows - 1, cy + extent);
        y++
      ) {
        for (
          var x = math.max(0, cx - extent);
          x <= math.min(columns - 1, cx + extent);
          x++
        ) {
          if (math.max((x - cx).abs(), (y - cy).abs()) != extent) continue;
          final candidate = index(x, y);
          if (blocked[candidate]) continue;
          final d = (gridPoint(candidate) - position).distanceSquared;
          if (d < distance) {
            distance = d;
            best = candidate;
          }
        }
      }
      if (best >= 0) break;
    }
    return best;
  }

  // A binary min-heap avoids the quadratic scans of sorting the open set.
  List<int> pathFind(int start, int goal, List<bool> blocked) {
    final costs = List<double>.filled(count, double.infinity);
    final parent = List<int>.filled(count, -1);
    final visited = List<bool>.filled(count, false);
    final heap = <(int, double)>[];
    void push(int point, double score) {
      var i = heap.length;
      heap.add((point, score));
      while (i > 0) {
        final parentIndex = (i - 1) ~/ 2;
        if (heap[parentIndex].$2 <= score) break;
        heap[i] = heap[parentIndex];
        i = parentIndex;
      }
      heap[i] = (point, score);
    }

    (int, double) pop() {
      final first = heap.first;
      final last = heap.removeLast();
      if (heap.isEmpty) return first;
      var i = 0;
      while (i * 2 + 1 < heap.length) {
        var child = i * 2 + 1;
        if (child + 1 < heap.length && heap[child + 1].$2 < heap[child].$2) {
          child++;
        }
        if (heap[child].$2 >= last.$2) break;
        heap[i] = heap[child];
        i = child;
      }
      heap[i] = last;
      return first;
    }

    double heuristic(int i) => (gridPoint(goal) - gridPoint(i)).distance;
    costs[start] = 0;
    push(start, heuristic(start));
    while (heap.isNotEmpty) {
      final current = pop().$1;
      if (visited[current]) continue;
      if (current == goal) {
        final route = <int>[];
        var cursor = goal;
        while (cursor >= 0) {
          route.add(cursor);
          cursor = parent[cursor];
        }
        return route.reversed.toList();
      }
      visited[current] = true;
      final x = current % columns;
      final y = current ~/ columns;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= columns || ny >= rows) continue;
          final neighbour = index(nx, ny);
          if (blocked[neighbour] || visited[neighbour]) continue;
          if (dx != 0 &&
              dy != 0 &&
              (blocked[index(nx, y)] || blocked[index(x, ny)])) {
            continue;
          }
          final nextCost =
              costs[current] + (dx != 0 && dy != 0 ? step * math.sqrt2 : step);
          if (nextCost >= costs[neighbour]) continue;
          costs[neighbour] = nextCost;
          parent[neighbour] = current;
          push(neighbour, nextCost + heuristic(neighbour));
        }
      }
    }
    return const [];
  }

  final paths = <List<Offset>>[];
  for (var portIndex = 0; portIndex < requests.length; portIndex++) {
    final port = requests[portIndex];
    final obstacles = [
      ...staticObstacles,
      for (var i = 0; i < requests.length; i++)
        if (i != portIndex) requests[i].badge.inflate(3),
    ];
    final blocked = List<bool>.generate(
      count,
      (i) => !isClear(gridPoint(i), obstacles, step * .68 + 1),
    );
    final normal = port.shore - size.center(Offset.zero);
    final outward = normal.distance > 0
        ? normal / normal.distance
        : const Offset(0, -1);
    Offset? seed;
    for (var distance = 4.0; distance < radius * 1.5 + 35; distance += 2) {
      final candidate = port.shore + outward * distance;
      if (!isClear(candidate, obstacles, step * .65 + 1)) continue;
      if (!clearLine(port.shore, candidate, obstacles, startingAtShore: true)) {
        continue;
      }
      seed = candidate;
      break;
    }
    if (seed == null) {
      paths.add([port.shore, port.badge.center]);
      continue;
    }
    final start = nearestFree(seed, blocked);
    final goal = nearestFree(port.badge.center, blocked);
    if (start < 0 || goal < 0) {
      paths.add([port.shore, port.badge.center]);
      continue;
    }
    final nodes = pathFind(start, goal, blocked);
    if (nodes.isEmpty) {
      paths.add([port.shore, port.badge.center]);
      continue;
    }
    final raw = <Offset>[seed, ...nodes.map(gridPoint), port.badge.center];
    final cleaned = <Offset>[raw.first];
    var cursor = 0;
    while (cursor < raw.length - 1) {
      var next = cursor + 1;
      for (var j = raw.length - 1; j > cursor + 1; j--) {
        if (clearLine(raw[cursor], raw[j], obstacles)) {
          next = j;
          break;
        }
      }
      cleaned.add(raw[next]);
      cursor = next;
    }
    if (cleaned.length > 2 &&
        clearLine(port.shore, cleaned[1], obstacles, startingAtShore: true)) {
      cleaned.removeAt(0);
    }
    final points = <Offset>[port.shore, ...cleaned];
    // Stop the stroke at the frame rather than painting across the label.
    if (points.length >= 2) {
      final from = points[points.length - 2];
      final to = port.badge.center;
      final delta = to - from;
      final xFraction = delta.dx.abs() < .001
          ? double.infinity
          : (port.badge.width / 2) / delta.dx.abs();
      final yFraction = delta.dy.abs() < .001
          ? double.infinity
          : (port.badge.height / 2) / delta.dy.abs();
      points[points.length - 1] = to - delta * math.min(xFraction, yFraction);
    }
    paths.add(points);
  }
  if (_routeCache.length >= 16) _routeCache.remove(_routeCache.keys.first);
  _routeCache[key] = paths;
  return paths;
}
