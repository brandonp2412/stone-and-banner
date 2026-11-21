import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/match_archive.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'expanded cards do not alter legacy replay shuffles or card positions',
    () {
      final old = MatchEngine.newGame(['A', 'B', 'C'], 51);
      final newMatch = MatchEngine.newGame(
        ['A', 'B', 'C'],
        51,
        cardDeckVersion: 2,
      );
      expect(old.cardDeckVersion, 1);
      expect(newMatch.cardDeckVersion, 2);
      expect(
        newMatch.drawPiles[StrategyDeck.governance]!.length,
        greaterThan(old.drawPiles[StrategyDeck.governance]!.length),
      );
      final oldReplay =
          jsonDecode(MatchEngine.exportReplay(old)) as Map<String, dynamic>;
      oldReplay.remove('cardDeckVersion');
      final restored = MatchEngine.importReplay(jsonEncode(oldReplay));
      expect(restored.cardDeckVersion, 1);
      expect(
        restored.drawPiles[StrategyDeck.governance],
        old.drawPiles[StrategyDeck.governance],
      );
      expect(
        StrategyCards.expandedDeck(StrategyDeck.governance)
            .take(StrategyCards.deck(StrategyDeck.governance).length)
            .toList(),
        StrategyCards.deck(StrategyDeck.governance),
      );
    },
  );

  test(
    'Royal Audit confiscates exactly one good per rival, deterministically',
    () {
      final base = MatchEngine.newGame(['A', 'B', 'C'], 52, cardDeckVersion: 2);
      final index = StrategyCards.expandedDeck(StrategyDeck.governance)
          .indexWhere((c) => c.id == 'royal-audit');
      expect(index, greaterThanOrEqualTo(0));
      final players = base.players.toList();
      players[0] = players[0].copyWith(
        cards: [HeldCard(StrategyDeck.governance, index)],
      );
      players[1] = players[1].copyWith(stores: {Resource.wood: 2});
      players[2] = players[2].copyWith(stores: {Resource.ore: 1});
      final pile = base.drawPiles[StrategyDeck.governance]!.toList()
        ..remove(index);
      final state = base.copyWith(
        phase: MatchPhase.actions,
        players: players,
        bank: {...base.bank, Resource.wood: 17, Resource.ore: 18},
        drawPiles: {...base.drawPiles, StrategyDeck.governance: pile},
      );
      final actions = MatchEngine.legalCardPlays(state, 0);
      expect(actions, hasLength(1));
      final outcome = MatchEngine.apply(state, actions.single);
      expect(outcome.players[0].stores[Resource.wood], 1);
      expect(outcome.players[0].stores[Resource.ore], 1);
      expect(outcome.players[1].stores[Resource.wood], 1);
      expect(outcome.players[2].stores[Resource.ore], 0);
      expect(outcome.players[0].cards, isEmpty);
      for (final good in Resource.values) {
        expect(
          outcome.bank[good]! +
              outcome.players.fold<int>(
                0,
                (sum, p) => sum + (p.stores[good] ?? 0),
              ),
          19,
        );
      }
    },
  );

  test('Mass Suspension chooses a hex and leaves distant Knights active', () {
    final base = MatchEngine.newGame(['A', 'B', 'C'], 53, cardDeckVersion: 2);
    final tileVertices = base.topology.tileVertices[0];
    final near = tileVertices.first;
    final far = base.topology.vertices
        .firstWhere((vertex) => !tileVertices.contains(vertex.id))
        .id;
    final index = StrategyCards.expandedDeck(StrategyDeck.governance)
        .indexWhere((c) => c.id == 'mass-suspension');
    final players = base.players.toList();
    players[0] = players[0].copyWith(
      cards: [HeldCard(StrategyDeck.governance, index)],
    );
    final state = base.copyWith(
      phase: MatchPhase.actions,
      players: players,
      knights: {
        near: const KnightPiece(1, KnightRank.sentinel, true, -1),
        far: const KnightPiece(2, KnightRank.warden, true, -1),
      },
    );
    final plays = MatchEngine.legalCardPlays(state, 0);
    expect(plays.any((option) => option.tile == 0), isTrue);
    final result = MatchEngine.apply(
      state,
      plays.firstWhere((option) => option.tile == 0),
    );
    expect(result.knights[near]!.active, isFalse);
    expect(result.knights[far]!.active, isTrue);
  });

  test('invasion asks the active human and every bot, even without aid', () {
    final state = MatchEngine.newGame(
      ['Human', 'Bot1', 'Bot2'],
      20261121,
    ).copyWith(phase: MatchPhase.actions, active: 2, reaverPressure: 5);
    final invasion = MatchEngine.apply(state, const EndTurn());
    expect(invasion.phase, MatchPhase.invasion);
    expect(invasion.tactical?.responders, [0, 1, 2]);
    final passed = MatchEngine.apply(
      invasion,
      RespondTactical(invasion.tactical!.id, 0, TacticalChoice.pass),
    );
    expect(passed.tactical?.responder, 1);
  });

  test('robber interception requires an active knight on robbed hex', () {
    final base = MatchEngine.newGame(['A', 'B', 'C'], 55);
    final tile = base.topology.tileVertices[0];
    final remote = base.topology.vertices
        .firstWhere((v) => !tile.contains(v.id))
        .id;
    final elsewhere = base.copyWith(
      knights: {remote: KnightPiece(1, KnightRank.sentinel, true, -1)},
    );
    expect(MatchEngine.canIntercept(elsewhere, 1, tile: 0), isFalse);
    final sameHex = base.copyWith(
      knights: {tile.first: KnightPiece(1, KnightRank.sentinel, true, -1)},
    );
    expect(MatchEngine.canIntercept(sameHex, 1, tile: 0), isTrue);
    expect(
      MatchEngine.canIntercept(
        sameHex.copyWith(reactionsUsed: {1}),
        1,
        tile: 0,
      ),
      isFalse,
    );
  });

  test('enemy knight blocks road extension and interrupts longest road', () {
    final base = MatchEngine.newGame(['A', 'B', 'C'], 56);
    final vertex = base.topology.vertices.firstWhere((v) => v.edges.length > 1);
    final firstEdge = vertex.edges[0], nextEdge = vertex.edges[1];
    final roads = {firstEdge: 0};
    final stores = {for (final r in Resource.values) r: 15};
    final players = base.players.toList();
    players[0] = players[0].copyWith(stores: stores);
    final unblocked = base.copyWith(
      phase: MatchPhase.actions,
      players: players,
      roads: roads,
    );
    expect(MatchEngine.legalRoad(unblocked, nextEdge), isTrue);
    final blocked = unblocked.copyWith(
      knights: {vertex.id: KnightPiece(1, KnightRank.sentinel, false, -1)},
    );
    expect(MatchEngine.legalRoad(blocked, nextEdge), isFalse);
    final twoRoads = blocked.copyWith(roads: {firstEdge: 0, nextEdge: 0});
    expect(MatchEngine.longestRoad(twoRoads, 0), 1);
  });

  test('bot trade targets must be able to produce requested goods', () {
    final base = MatchEngine.newGame(['Human', 'Bot', 'Other'], 57);
    final vertex = base.topology.vertices.firstWhere(
      (v) =>
          v.tiles.any((tile) => base.board.tiles[tile].land.produces != null),
    );
    final resource = base
        .board
        .tiles[vertex.tiles.firstWhere(
          (tile) => base.board.tiles[tile].land.produces != null,
        )]
        .land
        .produces!;
    final state = base.copyWith(
      sites: {vertex.id: const Site(0, Structure.village)},
    );
    expect(AiActionAdapter.recipientCanProduce(state, 0, resource), isTrue);
    expect(
      AiActionAdapter.recipientCanProduce(state, 0, Resource.cloth),
      isFalse,
    );
    expect(AiActionAdapter.recipientCanProduce(state, 2, resource), isFalse);
  });

  test(
    'archive stores separate replay, monthly index and deduplicates',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final base = MatchEngine.newGame(['A', 'B', 'C'], 58);
      final state = MatchEngine.apply(base, const PlaceVillage(0));
      await MatchArchive.save(prefs, state);
      await MatchArchive.save(prefs, state);
      final archived = await MatchArchive.list(prefs);
      expect(archived, hasLength(1));
      expect(archived.single.eventCount, 1);
      expect(
        MatchEngine.importReplay(MatchArchive.replay(prefs, archived.single)!)
            .events
            .length,
        1,
      );
      expect(prefs.getStringList(MatchArchive.monthsKey), hasLength(1));
      final month = prefs.getStringList(MatchArchive.monthsKey)!.single;
      final index = prefs.getStringList('stone_banner_archive_index_v1_$month');
      expect(index, hasLength(1));
      expect(index!.single.length, lessThan(600));
    },
  );

  test('debug log stores per-event goods deltas in bounded chunks', () async {
    final prefs = await SharedPreferences.getInstance();
    final base = MatchEngine.newGame(['A', 'B', 'C'], 59);
    final state = MatchEngine.apply(base, const PlaceVillage(0));
    await DebugMatchLog.append(prefs, base, state);
    await DebugMatchLog.append(prefs, base, state);
    final rows = jsonDecode(
      prefs.getString('stone_banner_debug_event_v1_59_0')!,
    ) as List;
    expect(rows, hasLength(1));
    expect(rows.single['event']['type'], 'village');
  });
}
