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
  testWidgets('bank exchange uses focused route, conserves stock and returns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var s = drafted().copyWith(phase: MatchPhase.actions);
    for (var i = 0; i < 4; i++) {
      s = grant(s, 0, Resource.wood);
    }
    var updated = s;
    final woodBefore = s.players[0].stores[Resource.wood]!;
    final woolBefore = s.players[0].stores[Resource.wool] ?? 0;
    final bankWoodBefore = s.bank[Resource.wood]!;
    final bankWoolBefore = s.bank[Resource.wool]!;
    await showMatch(tester, s, (v) => updated = v);
    await tester.scrollUntilVisible(find.text('Bank trade'), 250);
    await tester.tap(find.text('Bank trade'));
    await tester.pumpAndSettle();
    expect(find.text('Bank exchange'), findsOneWidget);
    expect(find.textContaining('Rate 4:1'), findsOneWidget);
    expect(find.text('End turn'), findsNothing);
    expect(find.text('Exchange'), findsOneWidget);
    await tester.tap(find.text('Exchange'));
    await tester.pumpAndSettle();
    expect(updated.players[0].stores[Resource.wood], woodBefore - 4);
    expect(updated.players[0].stores[Resource.wool], woolBefore + 1);
    expect(updated.bank[Resource.wood], bankWoodBefore + 4);
    expect(updated.bank[Resource.wool], bankWoolBefore - 1);
    expect(find.text('Bank exchange'), findsNothing);
  });

  testWidgets('standing offer reserves only once on its focused route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = grant(
      drafted().copyWith(phase: MatchPhase.actions),
      0,
      Resource.wood,
    );
    var updated = s;
    final before = s.players[0].stores[Resource.wood]!;
    await showMatch(tester, s, (v) => updated = v);
    await tester.scrollUntilVisible(find.text('Player trade'), 250);
    await tester.tap(find.text('Player trade'));
    await tester.pumpAndSettle();
    expect(find.text('Standing offer'), findsOneWidget);
    expect(find.textContaining('Private hands stay hidden'), findsOneWidget);
    expect(find.text('End turn'), findsNothing);
    await tester.tap(find.text('Escrow and offer'));
    await tester.pumpAndSettle();
    expect(updated.offers, hasLength(1));
    expect(updated.offers.single.give, Resource.wood);
    expect(updated.players[0].stores[Resource.wood], before - 1);
    expect(find.text('Standing offer'), findsNothing);
  });

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
