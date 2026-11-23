import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

void main() {
  test('coastal docks grant owner-specific and good-specific rates', () {
    final base = MatchEngine.newGame(['A', 'B', 'C'], 55);
    final docks = base.topology.docks;
    expect(docks.length, 9);
    expect(docks.map((d) => d.edge.id).toSet().length, 9);
    for (final dock in docks) {
      expect(dock.edge.tiles.length, 1);
      final s = base.copyWith(
        sites: {dock.edge.a: const Site(0, Structure.village)},
      );
      expect(MatchEngine.tradeRate(s, 1, Resource.wood), 4);
      if (dock.resource == null) {
        for (final good in Resource.values) {
          expect(MatchEngine.tradeRate(s, 0, good), 3);
        }
      } else {
        expect(MatchEngine.tradeRate(s, 0, dock.resource), 2);
        expect(MatchEngine.tradeRate(s, 0, Resource.coin), 4);
      }
    }
  });

  test('bank exchange pays actual dock rate and replay preserves docks', () {
    final base = MatchEngine.newGame(['A', 'B', 'C'], 55);
    final dock = base.topology.docks.firstWhere(
      (d) => d.resource == Resource.wood,
    );
    final players = base.players.toList();
    players[0] = players[0].copyWith(
      stores: {...players[0].stores, Resource.wood: 2},
    );
    final s = base.copyWith(
      phase: MatchPhase.actions,
      players: players,
      sites: {dock.edge.a: const Site(0, Structure.village)},
    );
    final next = MatchEngine.apply(
      s,
      const BankExchange(Resource.wood, Resource.ore),
    );
    expect(next.players[0].stores[Resource.wood], 0);
    expect(
      next.players[0].stores[Resource.ore],
      (s.players[0].stores[Resource.ore] ?? 0) + 1,
    );
    expect(
      MatchEngine.importReplay(MatchEngine.exportReplay(base)).topology.docks
          .map((d) => d.edge.id),
      base.topology.docks.map((d) => d.edge.id),
    );
  });

  for (final defended in [true, false]) {
    test('invasion exhausts guards after ${defended ? "defence" : "raid"}', () {
      final base = MatchEngine.newGame(['A', 'B', 'C'], 55);
      final s = base.copyWith(
        phase: MatchPhase.invasion,
        sites: {
          0: const Site(0, Structure.town),
          1: const Site(1, Structure.capital),
        },
        guards: {
          3: GuardPiece(
            0,
            defended ? GuardRank.champion : GuardRank.sentinel,
            true,
            -1,
          ),
          4: const GuardPiece(1, GuardRank.sentinel, false, -1),
        },
      );
      final next = MatchEngine.apply(s, const ResolveInvasion());
      expect(next.guards.values.every((k) => !k.active), isTrue);
    });
  }
}
