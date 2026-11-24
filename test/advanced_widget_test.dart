import 'action_helpers.dart';

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
  testWidgets('build stays visible and disabled before rolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ready = readyBoard();
    Future<void> show(MatchState state) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MatchView(state: state, onEvent: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(ready);
    expect(find.text('Road'), findsOneWidget);
    await show(ready.copyWith(phase: MatchPhase.roll));
    expect(find.text('Road'), findsOneWidget);
    final road = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Road'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(road.onPressed, isNull);
    expect(find.text('Your turn begins'), findsNothing);
    expect(
      find.textContaining('Production goes to every eligible'),
      findsNothing,
    );
    await show(ready);
    await tester.tap(find.text('Realm'));
    await tester.pumpAndSettle();
    await show(ready.copyWith(phase: MatchPhase.roll));
    expect(find.text('Your realm'), findsOneWidget);
    expect(find.text('Road'), findsNothing);
  });

  testWidgets('touch a Town Development and recruit Guard on board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
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
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Your realm');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Town Developments'));
    expect(find.text('Town Developments'), findsOneWidget);
    await tester.ensureVisible(find.text('Town Developments'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scriptorium'), findsOneWidget);
    await tester.ensureVisible(find.text('Develop innovation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Develop innovation').hitTestable());
    await tester.pumpAndSettle();
    expect(s.current.level(StrategyDeck.innovation), 1);

    final vertex = [
      for (var v = 0; v < s.topology.vertices.length; v++)
        if (MatchEngine.legalRecruit(s, v)) v,
    ].first;

    await scrollToAction(tester, 'Road');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Recruit Guard'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recruit Guard'));
    await tester.pumpAndSettle();
    final board = find.byKey(const ValueKey('realm-map'));
    // The map stays visible while the action panel scrolls.
    await tester.pumpAndSettle();
    final size = tester.getSize(board);
    final origin = tester.getTopLeft(board);
    await tester.tapAt(
      origin + BoardGeometry(size).vertex(s.topology.vertices[vertex]),
    );
    await tester.pumpAndSettle();
    expect(s.guards[vertex]?.owner, 0);
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
    await tester.ensureVisible(find.text('Resolve'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Defence ${MatchEngine.defenceStrength(s) + s.invasionAid} / ${MatchEngine.invasionStrength(s)}',
      ),
      findsWidgets,
    );
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();
    expect(s.phase, MatchPhase.roll);
    expect(find.text('Roll'), findsOneWidget);
  });
}
