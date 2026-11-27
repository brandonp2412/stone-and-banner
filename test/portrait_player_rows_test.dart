import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/engine/match.dart';

import 'portrait_visual_audit_test.dart' show portraitSetup, renderMatch;
import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets(
    'tall portrait displays all players without reducing board radius',
    (tester) async {
      await portraitSetup(tester);
      await renderMatch(tester);
      final tiles = List.generate(
        4,
        (i) => find.byKey(ValueKey('player-tile-$i')),
      );
      final rows = tiles.map((tile) => tester.getTopLeft(tile).dy).toSet();
      expect(rows, hasLength(2));
      for (final tile in tiles) {
        expect(tester.getRect(tile).right, lessThanOrEqualTo(393));
      }
      final geometry = BoardGeometry(
        tester.getSize(find.byKey(const ValueKey('realm-map'))),
      );
      expect(geometry.isPortrait, isTrue);
      expect(geometry.radius, closeTo(393 / 9.4, .001));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/portrait_player_rows.png'),
      );
    },
  );

  testWidgets('short portrait preserves board size with one scrolling row', (
    tester,
  ) async {
    await portraitSetup(tester);
    tester.view.physicalSize = const Size(393, 650);
    await renderMatch(tester, state: tableWithSupplies());
    final first = tester.getTopLeft(
      find.byKey(const ValueKey('player-tile-0')),
    );
    final last = tester.getTopLeft(find.byKey(const ValueKey('player-tile-3')));
    expect(last.dy, first.dy);
    final geometry = BoardGeometry(
      tester.getSize(find.byKey(const ValueKey('realm-map'))),
    );
    expect(geometry.size.height, closeTo(650 - 52 - 99.6, 1));
  });
  testWidgets('six players fit across two rows on tall portrait', (
    tester,
  ) async {
    await portraitSetup(tester);
    tester.view.physicalSize = const Size(340, 852);
    await renderMatch(
      tester,
      state: MatchEngine.newGame([
        'Ada',
        'Ben',
        'Cora',
        'Dee',
        'Eli',
        'Fay',
      ], 804),
    );
    final tiles = List.generate(
      6,
      (i) => find.byKey(ValueKey('player-tile-$i')),
    );
    expect(
      tiles.map((tile) => tester.getTopLeft(tile).dy).toSet(),
      hasLength(2),
    );
    for (final tile in tiles) {
      expect(tester.getRect(tile).right, lessThanOrEqualTo(340));
    }
    expect(
      BoardGeometry(tester.getSize(find.byKey(const ValueKey('realm-map'))))
          .radius,
      closeTo(340 / 9.4, .001),
    );
  });
}
