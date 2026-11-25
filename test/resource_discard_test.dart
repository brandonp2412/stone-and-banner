import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'advanced_test.dart' show draft, fund;
import 'new_gameplay_widget_test.dart' show capture;

MatchState seven() {
  var state = draft(55).copyWith(phase: MatchPhase.roll);
  final players = state.players.toList();
  for (var i = 0; i < players.length; i++) {
    players[i] = players[i].copyWith(
      stores: {
        for (final r in Resource.values) r: 0,
        if (i == 0) Resource.wood: 5,
        if (i == 0) Resource.wheat: 4,
      },
    );
  }
  state = state.copyWith(players: players);
  while (true) {
    final (a, b) = MatchEngine.expectedDice(state);
    if (a + b == 7) return state;
    state = state.copyWith(rollCount: state.rollCount + 1);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await loader.load();
  });

  test(
    'seven waits for a validated choice and returns chosen goods to bank',
    () {
      final before = seven();
      final (a, b) = MatchEngine.expectedDice(before);
      final rolled = MatchEngine.apply(before, RollDice(a, b));
      expect(rolled.pendingDiscards, {0: 4});
      expect(rolled.players[0].stores, before.players[0].stores);
      expect(() => MatchEngine.apply(rolled, MoveBandit(0)), throwsStateError);
      for (final goods in [
        {Resource.wood: 3},
        {Resource.wheat: 5, Resource.wood: -1},
        {Resource.ore: 4},
      ]) {
        expect(
          () => MatchEngine.apply(rolled, DiscardResources(0, goods)),
          throwsStateError,
        );
      }
      final event = DiscardResources(0, {Resource.wheat: 4});
      final after = MatchEngine.apply(rolled, event);
      expect(after.pendingDiscards, isEmpty);
      expect(after.players[0].stores[Resource.wood], 5);
      expect(after.players[0].stores[Resource.wheat], 0);
      expect(after.bank[Resource.wheat], rolled.bank[Resource.wheat]! + 4);
      final wire = RoomProtocol.eventFromJson(
        jsonDecode(jsonEncode(event.toJson())),
      );
      expect(wire.toJson(), event.toJson());
      final view = RoomProtocol.readView(RoomProtocol.view(rolled, 0));
      expect(view.pendingDiscards, {0: 4});
      expect(const HeuristicAi().choose(rolled), isA<DiscardResources>());
      final legacy = MatchEngine.apply(
        before,
        RollDice(a, b, chooseDiscards: false),
      );
      expect(legacy.pendingDiscards, isEmpty);
      expect(legacy.players[0].stores.values.fold<int>(0, (a, b) => a + b), 5);
    },
  );

  testWidgets('modal requires exact selection and submits chosen resources', (
    tester,
  ) async {
    final before = seven();
    final (a, b) = MatchEngine.expectedDice(before);
    final state = MatchEngine.apply(before, RollDice(a, b));
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(state: state, onEvent: events.add),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Discard 4 resources');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    for (var i = 0; i < 4; i++) {
      await tester.tap(
        find.byKey(const ValueKey('transfer-DISCARD-add-wheat')),
      );
      await tester.pump();
    }
    expect(find.text('4 / 4 selected'), findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect((events.single as DiscardResources).goods, {Resource.wheat: 4});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('minimized discard prevents bandit targeting until resolved', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = seven().copyWith(active: 1, phase: MatchPhase.actions);
    state = fund(state, 1, MatchEngine.effectiveRoadCost(state));
    state = MatchEngine.apply(
      state,
      PlaceRoad(MatchEngine.legalEdges(state).first),
    );
    state = fund(state, 1, {Resource.wood: 1});
    state = state.copyWith(active: 0, phase: MatchPhase.roll);
    final (a, b) = MatchEngine.expectedDice(state);
    state = MatchEngine.apply(state, RollDice(a, b));
    final tile = List.generate(state.board.tiles.length, (i) => i).firstWhere(
      (i) =>
          i != state.banditTile &&
          MatchEngine.banditVictims(state, i).contains(1),
    );
    final events = <MatchEvent>[];
    Widget screen() => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
      home: Scaffold(
        body: MatchView(state: state, onEvent: events.add),
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('minimize-discard')));
    await tester.pumpAndSettle();
    final map = find.byKey(const ValueKey('realm-map'));
    final point =
        tester.getTopLeft(map) +
        BoardGeometry(tester.getSize(map))
            .tile(state.board.tiles[tile].position);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(find.text('Bandit · choose who to rob'), findsNothing);
    expect(events, isEmpty);
    expect(find.text('Discard resources'), findsWidgets);
    expect(find.text('Move the Bandit'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('restore-discard')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(
        find.byKey(const ValueKey('transfer-DISCARD-add-wheat')),
      );
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Discard 4 resources'));
    await tester.pumpAndSettle();
    state = MatchEngine.apply(state, events.removeLast());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(find.text('Bandit · choose who to rob'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('online status identifies the discarding seat, not roller', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = seven().copyWith(active: 1);
    final (a, b) = MatchEngine.expectedDice(before);
    final state = MatchEngine.apply(before, RollDice(a, b));
    expect(state.actingSeat, 0);
    expect(state.active, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(
          state: state,
          online: true,
          visibleSeat: 1,
          observing: true,
          onEvent: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final status = find.byKey(const ValueKey('acting-player-status'));
    expect(status, findsOneWidget);
    expect(tester.widget<Text>(status).data, state.players[0].id);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('turn flag and countdown follow the required discard player', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = seven().copyWith(active: 1);
    final (a, b) = MatchEngine.expectedDice(before);
    final state = MatchEngine.apply(before, RollDice(a, b));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        builder: (_, child) =>
            RepaintBoundary(key: const ValueKey('capture'), child: child!),
        home: MatchView(
          state: state,
          online: true,
          visibleSeat: 1,
          observing: true,
          onEvent: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    Finder tile(int seat) => find.byKey(ValueKey('player-tile-$seat'));
    expect(
      find.descendant(of: tile(0), matching: find.byIcon(Icons.flag_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile(1), matching: find.byIcon(Icons.flag_rounded)),
      findsNothing,
    );
    expect(
      find.descendant(of: tile(0), matching: find.textContaining('Discard')),
      findsOneWidget,
    );
    if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
      await tester.runAsync(
        () => capture(
          tester,
          '/tmp/stone-bughunt-1909/discard-acting-player.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
}
