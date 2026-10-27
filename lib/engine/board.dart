enum Resource { wood, brick, wheat, wool, ore, paper, cloth, coin }

enum Land { woodland, clayBeds, fields, meadows, ridges, barren }

extension LandYield on Land {
  Resource? get produces => switch (this) {
    Land.woodland => Resource.wood,
    Land.clayBeds => Resource.brick,
    Land.fields => Resource.wheat,
    Land.meadows => Resource.wool,
    Land.ridges => Resource.ore,
    Land.barren => null,
  };
}

class HexCoord {
  const HexCoord(this.q, this.r);
  final int q, r;
  bool touches(HexCoord other) {
    final dq = q - other.q, dr = r - other.r;
    return (dq.abs() + dr.abs() + (dq + dr).abs()) ~/ 2 == 1;
  }

  @override
  bool operator ==(Object other) =>
      other is HexCoord && q == other.q && r == other.r;
  @override
  int get hashCode => Object.hash(q, r);
}

class HexTile {
  const HexTile(this.position, this.land, this.productionNumber);
  final HexCoord position;
  final Land land;
  final int? productionNumber;
  @override
  bool operator ==(Object other) =>
      other is HexTile &&
      position == other.position &&
      land == other.land &&
      productionNumber == other.productionNumber;
  @override
  int get hashCode => Object.hash(position, land, productionNumber);
}

class Board {
  Board(this.seed, List<HexTile> tiles) : tiles = List.unmodifiable(tiles);
  final int seed;
  final List<HexTile> tiles;
}

// Explicit 32-bit PRNG preserves replays across Dart runtimes and versions.
class _SeededRandom {
  _SeededRandom(int seed)
    : _state = (seed & 0xffffffff) == 0 ? 0x6d2b79f5 : seed & 0xffffffff;
  int _state;
  int nextInt(int max) {
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _state = x & 0xffffffff;
    return _state % max;
  }

  List<T> shuffle<T>(List<T> original) {
    final result = List<T>.of(original);
    for (var i = result.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = result[i];
      result[i] = result[j];
      result[j] = tmp;
    }
    return result;
  }
}

class BoardGenerator {
  static final _coords = [
    for (var q = -2; q <= 2; q++)
      for (var r = -2; r <= 2; r++)
        if ((q + r).abs() <= 2) HexCoord(q, r),
  ];
  static final _terrain = [
    ...List.filled(4, Land.woodland),
    ...List.filled(3, Land.clayBeds),
    ...List.filled(4, Land.fields),
    ...List.filled(4, Land.meadows),
    ...List.filled(3, Land.ridges),
    Land.barren,
  ];
  static final _numbers = [
    2,
    12,
    for (final n in [3, 4, 5, 6, 8, 9, 10, 11]) ...[n, n],
  ];
  static final _neighbors = [
    for (var i = 0; i < _coords.length; i++)
      for (var j = i + 1; j < _coords.length; j++)
        if (_coords[i].touches(_coords[j])) (i, j),
  ];
  static final _vertices = [
    for (var i = 0; i < _coords.length; i++)
      for (var j = i + 1; j < _coords.length; j++)
        if (_coords[i].touches(_coords[j]))
          for (var k = j + 1; k < _coords.length; k++)
            if (_coords[i].touches(_coords[k]) &&
                _coords[j].touches(_coords[k]))
              (i, j, k),
  ];

  static Board generate(int seed) {
    final rng = _SeededRandom(seed);
    for (var attempt = 0; attempt < 10000; attempt++) {
      final lands = rng.shuffle(_terrain);
      if (_vertices.any((v) {
        final (a, b, c) = v;
        return lands[a] == lands[b] && lands[b] == lands[c];
      })) {
        continue;
      }
      final iterator = rng.shuffle(_numbers).iterator;
      final tiles = [
        for (var i = 0; i < _coords.length; i++)
          HexTile(
            _coords[i],
            lands[i],
            lands[i] == Land.barren ? null : (iterator..moveNext()).current,
          ),
      ];
      if (_neighbors.any((p) {
        final (a, b) = p;
        final x = tiles[a].productionNumber, y = tiles[b].productionNumber;
        return (x == 6 || x == 8) && (y == 6 || y == 8);
      })) {
        continue;
      }
      return Board(seed, tiles);
    }
    throw StateError('Unable to generate balanced board for seed $seed');
  }
}
