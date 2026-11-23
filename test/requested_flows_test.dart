import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/ai_turn_coordinator.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_harvest.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  test('a sole active defender wins immediately when Honour reaches 15', () {
    final base = tableWithSupplies();
    final players = base.players.toList();
    players[0] = players[0].copyWith(guardianHonour: 11);
    final state = base.copyWith(
      phase: MatchPhase.invasion,
      invasionAid: 2,
      players: players,
      sites: {
        ...base.sites,
        base.sites.keys.first: const Site(0, Structure.town),
      },
      guards: {0: const GuardPiece(0, GuardRank.champion, true, -1)},
    );
    expect(MatchEngine.score(state, 0), 14);
    final after = MatchEngine.apply(state, const ResolveInvasion());
    expect(MatchEngine.score(after, 0), 15);
    expect(after.phase, MatchPhase.finished);
    expect(MatchEngine.winner(after), 0);
  });

  test(
    'inactive guards and tied active strength earn no sole-leader award',
    () {
      final base = tableWithSupplies();
      final state = base.copyWith(
        phase: MatchPhase.invasion,
        invasionAid: MatchEngine.invasionStrength(base),
        sites: {
          ...base.sites,
          base.sites.keys.first: const Site(0, Structure.town),
        },
        guards: {
          0: const GuardPiece(0, GuardRank.champion, false, -1),
          1: const GuardPiece(0, GuardRank.sentinel, true, -1),
          2: const GuardPiece(1, GuardRank.sentinel, true, -1),
        },
      );
      final after = MatchEngine.apply(state, const ResolveInvasion());
      expect(after.players[0].guardianHonour, 0);
      expect(after.players[1].guardianHonour, 0);
      expect(after.lastInvasion, contains('No sole Guard leader'));
    },
  );

  for (final accept in [true, false]) {
    test(
      'bot ${accept ? 'accepts' : 'refuses'} during the proposer’s turn',
      () async {
        final base = tableWithSupplies();
        final players = base.players.toList();
        players[1] = players[1].copyWith(
          stores: {
            for (final good in Resource.values) good: 0,
            Resource.coin: 1,
            Resource.ore: 1,
          },
        );
        var state = base.copyWith(players: players);
        state = MatchEngine.apply(
          state,
          ProposeTrade(
            1,
            accept ? Resource.ore : Resource.coin,
            1,
            accept ? Resource.coin : Resource.ore,
            1,
          ),
        );
        final coordinator = AiTurnCoordinator(
          read: () => state,
          commit: (expected, next) {
            expect(identical(state, expected), isTrue);
            state = next;
            return true;
          },
          isComputerSeat: (seat) => seat == 1,
          delay: Duration.zero,
          onError: (error) => fail(error.toString()),
        );
        coordinator.resume();
        await coordinator.settled;
        expect(state.active, 0);
        expect(state.offers, isEmpty);
        expect((state.events.last as RespondTrade).accept, accept);
        coordinator.pause();
      },
    );
  }

  testWidgets('tapping an active guard exposes and performs its upgrade', (
    tester,
  ) async {
    var state = tableWithSupplies();
    final vertex = state.sites.keys.firstWhere(
      (v) => state.sites[v]!.owner == 0,
    );
    state = state.copyWith(
      guards: {vertex: const GuardPiece(0, GuardRank.sentinel, true, -1)},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, refresh) => MatchView(
              state: state,
              onEvent: (event) =>
                  refresh(() => state = MatchEngine.apply(state, event)),
            ),
          ),
        ),
      ),
    );
    final map = find.byKey(const ValueKey('realm-map'));
    await tester.tapAt(
      tester.getTopLeft(map) +
          BoardGeometry(tester.getSize(map))
              .vertex(state.topology.vertices[vertex]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Upgrade cost:'), findsOneWidget);
    await tester.tap(find.text('Upgrade Guard'));
    await tester.pumpAndSettle();
    expect(state.guards[vertex]!.rank, GuardRank.warden);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turn reminder counts down in actions and resets next turn', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
    var state = tableWithSupplies();
    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, update) {
              refresh = update;
              return MatchView(state: state, onEvent: (_) {});
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Actions'));
    await tester.pump();
    expect(find.textContaining('1:30'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('1:28'), findsOneWidget);
    refresh(() => state = MatchEngine.apply(state, const EndTurn()));
    await tester.pump();
    expect(find.textContaining('1:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('harvest animates the actual goods credited by a roll', (
    tester,
  ) async {
    final before = tableWithSupplies();
    final players = before.players.toList();
    players[0] = players[0].copyWith(
      stores: {
        ...players[0].stores,
        Resource.wood: players[0].stores[Resource.wood]! + 2,
      },
    );
    Widget app(MatchState s) => MaterialApp(
      home: SizedBox(
        width: 400,
        height: 400,
        child: ResourceHarvest(
          state: s,
          seat: 0,
          anchors: {for (final r in Resource.values) r: LayerLink()},
        ),
      ),
    );
    await tester.pumpWidget(app(before));
    await tester.pumpWidget(
      app(before.copyWith(players: players, rollCount: before.rollCount + 1)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('+2 wood'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('+2 wood'), findsNothing);
  });
}
