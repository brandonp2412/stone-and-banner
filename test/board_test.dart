import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';

void main() {
  test('seed reproduces layout, distinct seeds differ', () {
    final first = BoardGenerator.generate(42);
    expect(BoardGenerator.generate(42).tiles, orderedEquals(first.tiles));
    expect(
      BoardGenerator.generate(43).tiles,
      isNot(orderedEquals(first.tiles)),
    );
  });

  test('19-hex terrain, token and adjacency invariants hold across seeds', () {
    for (var seed = 0; seed < 100; seed++) {
      final tiles = BoardGenerator.generate(seed).tiles;
      expect(tiles.length, 19);
      expect(tiles.map((tile) => tile.position).toSet().length, 19);
      for (final (land, count) in [
        (Land.woodland, 4),
        (Land.clayBeds, 3),
        (Land.fields, 4),
        (Land.meadows, 4),
        (Land.ridges, 3),
        (Land.barren, 1),
      ]) {
        expect(tiles.where((tile) => tile.land == land).length, count);
      }
      expect(tiles.where((tile) => tile.productionNumber != null).length, 18);
      final hot = tiles
          .where(
            (tile) => tile.productionNumber == 6 || tile.productionNumber == 8,
          )
          .toList();
      expect(hot.length, 4);
      for (var i = 0; i < tiles.length; i++) {
        for (var j = i + 1; j < tiles.length; j++) {
          final a = tiles[i], b = tiles[j];
          if (!a.position.touches(b.position)) continue;
          expect(hot.contains(a) && hot.contains(b), isFalse);
          for (var k = j + 1; k < tiles.length; k++) {
            final c = tiles[k];
            if (a.position.touches(c.position) &&
                b.position.touches(c.position)) {
              expect(a.land == b.land && b.land == c.land, isFalse);
            }
          }
        }
      }
    }
  });
}
