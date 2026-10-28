import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

MatchState readyBoard() {
  var s = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 100);
  for (var i = 0; i < 6; i++) {
    s = MatchEngine.apply(s, PlaceVillage(MatchEngine.legalVertices(s).first));
    s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
  }
  final vertex = s.sites.keys.firstWhere((v) => s.sites[v]!.owner == 0);
  final players = s.players.toList();
  final bank = Map<Resource, int>.of(s.bank);
  final goods = Map<Resource, int>.of(players[0].stores);
  for (final entry in {
    Resource.wheat: 3,
    Resource.ore: 5,
    Resource.wool: 1,
  }.entries) {
    bank[entry.key] = bank[entry.key]! - entry.value;
    goods[entry.key] = (goods[entry.key] ?? 0) + entry.value;
  }
  players[0] = players[0].copyWith(stores: goods);
  s = s.copyWith(players: players, bank: bank, phase: MatchPhase.actions);
  return MatchEngine.apply(s, UpgradeSite(vertex));
}

void main() {
  testWidgets('touch a Town Development and recruit Knight on board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var s = readyBoard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => MatchView(
              state: s,
              onEvent: (event) => update(() => s = MatchEngine.apply(s, event)),
            ),
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Town Developments'), 300);
    expect(find.text('Town Developments'), findsOneWidget);
    expect(find.textContaining('Scriptorium'), findsOneWidget);
    await tester.ensureVisible(find.text('Develop').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Develop').first);
    await tester.pumpAndSettle();
    expect(s.current.level(StrategyDeck.innovation), 1);

    final vertex = [
      for (var v = 0; v < s.topology.vertices.length; v++)
        if (MatchEngine.legalRecruit(s, v)) v,
    ].first;
    await tester.scrollUntilVisible(find.text('Recruit Knight'), -250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recruit Knight'));
    await tester.pumpAndSettle();
    final board = find.byType(InteractiveViewer);
    await tester.scrollUntilVisible(board, -300);
    await tester.pumpAndSettle();
    final size = tester.getSize(board);
    final origin = tester.getTopLeft(board);
    final radius = math.min(size.width / 9.8, size.height / 9.3);
    final v = s.topology.vertices[vertex];
    await tester.tapAt(
      origin +
          Offset(size.width / 2 + v.x * radius, size.height / 2 + v.y * radius),
    );
    await tester.pumpAndSettle();
    expect(s.knights[vertex]?.owner, 0);
  });

  testWidgets('Invasion preview resolves and returns to roll', (tester) async {
    var s = readyBoard().copyWith(
      phase: MatchPhase.invasion,
      reaverPressure: 3,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => MatchView(
              state: s,
              onEvent: (event) => update(() => s = MatchEngine.apply(s, event)),
            ),
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Resolve Invasion'), 300);
    await tester.pumpAndSettle();
    expect(find.textContaining('Fleet strength'), findsOneWidget);
    await tester.tap(find.text('Resolve Invasion'));
    await tester.pumpAndSettle();
    expect(s.phase, MatchPhase.roll);
    expect(find.text('Roll dice'), findsOneWidget);
  });
}
