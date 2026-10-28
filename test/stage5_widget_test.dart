import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

MatchState drafted() {
  var s = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 44);
  for (var i = 0; i < 6; i++) {
    s = MatchEngine.apply(s, PlaceVillage(MatchEngine.legalVertices(s).first));
    s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
  }
  return s;
}

MatchState grant(MatchState s, int player, Resource good) {
  final players = s.players.toList();
  players[player] = players[player].copyWith(
    stores: {
      ...players[player].stores,
      good: (players[player].stores[good] ?? 0) + 1,
    },
  );
  return s.copyWith(
    players: players,
    bank: {...s.bank, good: s.bank[good]! - 1},
  );
}

Future<void> showMatch(
  WidgetTester tester,
  MatchState initial,
  void Function(MatchState) updated,
) async {
  var state = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, refresh) => MatchView(
            state: state,
            onEvent: (event) => refresh(() {
              state = MatchEngine.apply(state, event);
              updated(state);
            }),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'private Bandit response has no acting hand and resolves by touch',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var s = grant(
        drafted().copyWith(phase: MatchPhase.bandit),
        1,
        Resource.ore,
      );
      final site = s.sites.entries.firstWhere((e) => e.value.owner == 1).key;
      final tile = s.topology.vertices[site].tiles.firstWhere(
        (v) => v != s.banditTile,
      );
      s = s.copyWith(
        knights: {0: const KnightPiece(1, KnightRank.sentinel, true, -1)},
      );
      s = MatchEngine.apply(s, MoveBandit(tile, victim: 1));
      var updated = s;
      await showMatch(tester, s, (v) => updated = v);
      expect(find.text('Response for Ben'), findsOneWidget);
      expect(find.text('Bandit interception'), findsOneWidget);
      expect(find.textContaining('Strategy hand'), findsNothing);
      expect(find.textContaining('wood '), findsNothing);
      await tester.ensureVisible(find.text('Intercept with Knight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intercept with Knight'));
      await tester.pumpAndSettle();
      expect(updated.tactical, isNull);
      expect(updated.knights[0]!.active, isFalse);
      expect(find.text('Bandit interception'), findsNothing);
    },
  );

  testWidgets('invasion aid and pass buttons advance responder without stall', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var s = drafted().copyWith(
      phase: MatchPhase.actions,
      active: 2,
      reaverPressure: 2,
    );
    s = grant(grant(s, 1, Resource.ore), 2, Resource.wheat);
    s = MatchEngine.apply(s, const EndTurn());
    expect(s.tactical, isNotNull);
    var updated = s;
    await showMatch(tester, s, (v) => updated = v);
    expect(find.text('Response for Ben'), findsOneWidget);
    await tester.ensureVisible(find.text('Pledge 1 ore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pledge 1 ore'));
    await tester.pumpAndSettle();
    expect(updated.invasionAid, 2);
    expect(find.text('Response for Cora'), findsOneWidget);
    await tester.tap(find.text('Pass'));
    await tester.pumpAndSettle();
    expect(updated.tactical, isNull);
    expect(find.text('Resolve Invasion'), findsOneWidget);
    expect(find.textContaining('Defence 2'), findsWidgets);
    expect(find.textContaining('Emergency aid +2'), findsOneWidget);
  });

  testWidgets('standing offer on another turn can be accepted in widget UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var s = grant(
      grant(drafted().copyWith(phase: MatchPhase.actions), 0, Resource.wood),
      1,
      Resource.ore,
    );
    s = MatchEngine.apply(
      s,
      const ProposeTrade(1, Resource.wood, 1, Resource.ore, 1),
    );
    s = MatchEngine.apply(s, const EndTurn());
    final pair = MatchEngine.expectedDice(s);
    s = MatchEngine.apply(s, RollDice(pair.$1, pair.$2));
    if (s.phase == MatchPhase.bandit) {
      s = MatchEngine.apply(
        s,
        MoveBandit((s.banditTile + 1) % s.board.tiles.length),
      );
    }
    var updated = s;
    await showMatch(tester, s, (v) => updated = v);
    await tester.scrollUntilVisible(find.text('Accept'), 250);
    await tester.pumpAndSettle();
    expect(find.text('Counter'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(updated.offers, isEmpty);
    expect(updated.players[1].stores[Resource.wood], greaterThanOrEqualTo(1));
  });
}
