import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

class NonlinearTestScaler extends TextScaler {
  const NonlinearTestScaler();

  @override
  double get textScaleFactor => 1.6;

  @override
  double scale(double size) => size <= 20
      ? size * 1.6
      : size < 40
      ? 32 + (size - 20) * .4
      : size;
}

MatchState tableWithSupplies() {
  var state = MatchEngine.newGame(['Ada', 'Ben', 'Cora', 'Dee'], 804);
  for (var i = 0; i < 8; i++) {
    state = MatchEngine.apply(
      state,
      PlaceVillage(MatchEngine.legalVertices(state).first),
    );
    state = MatchEngine.apply(
      state,
      PlaceRoad(MatchEngine.legalEdges(state).first),
    );
  }
  final bank = Map<Resource, int>.of(state.bank);
  final stores = Map<Resource, int>.of(state.current.stores);
  for (final good in Resource.values) {
    bank[good] = bank[good]! - 3;
    stores[good] = (stores[good] ?? 0) + 3;
  }
  final players = state.players.toList();
  players[state.active] = state.current.copyWith(stores: stores);
  return state.copyWith(
    phase: MatchPhase.actions,
    players: players,
    bank: bank,
  );
}

Future<void> display(
  WidgetTester tester,
  Size size,
  MatchState state, {
  double scale = 1,
  bool observing = false,
  ValueChanged<MatchEvent>? onEvent,
  TextScaler? textScaler,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await (FontLoader(
    'NotoSans',
  )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
  await tester.pumpWidget(
    MaterialApp(
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'NotoSans',
      ),
      home: Scaffold(
        body: MatchView(
          state: state,
          observing: observing,
          onEvent: onEvent ?? (_) {},
        ),
      ),
    ),
  );
  if (observing) {
    await tester.pump(const Duration(milliseconds: 100));
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('all four scores fit the compact standings', (tester) async {
    await display(tester, const Size(640, 320), tableWithSupplies());
    expect(find.text(' /15'), findsNWidgets(4));
    expect(
      tester.getRect(find.text(' /15').last).right,
      lessThanOrEqualTo(640 - 42),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact labels fit Android-style nonlinear text scaling', (
    tester,
  ) async {
    await display(
      tester,
      const Size(640, 320),
      tableWithSupplies(),
      textScaler: const NonlinearTestScaler(),
    );
    expect(tester.takeException(), isNull);
    for (final tab in ['Trade', 'Cards', 'Realm', 'Build']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('finished standings identify the winner and disable the turn', (
    tester,
  ) async {
    final before = tableWithSupplies();
    final players = before.players.toList();
    players[before.active] = before.current.copyWith(guardianHonour: 13);
    final state = before.copyWith(phase: MatchPhase.finished, players: players);
    final events = <MatchEvent>[];
    await display(tester, const Size(640, 320), state, onEvent: events.add);
    expect(find.text('Winner'), findsOneWidget);
    expect(find.text('Taking a turn'), findsNothing);
    final turn = find.widgetWithText(FilledButton, 'Match complete');
    expect(tester.widget<FilledButton>(turn).onPressed, isNull);
    expect(events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LAN inventory stays with the viewing seat during rival turns', (
    tester,
  ) async {
    final state = tableWithSupplies();
    final players = state.players.toList();
    players[1] = players[1].copyWith(
      stores: {...players[1].stores, Resource.wood: 7},
    );
    final canonical = state.copyWith(players: players);
    final view = RoomProtocol.view(canonical, 1);
    final filtered = RoomProtocol.readView(view);
    expect(filtered.current.stores[Resource.wood], 0);
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: filtered,
            online: true,
            onlineView: view,
            viewingSeat: 1,
            observing: true,
            waitingMessage: 'Waiting for Ada…',
            onEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('wood: 7'), findsOneWidget);
    expect(find.byTooltip('wood: 0'), findsNothing);
    expect(find.text('Computer turn'), findsNothing);
    expect(find.text('End turn'), findsNothing);
    expect(find.text('Waiting for Ada…'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final variant in [
    (const Size(640, 320), 1.0),
    (const Size(844, 390), 1.0),
    (const Size(844, 390), 1.6),
    (const Size(1024, 768), 2.0),
  ]) {
    testWidgets('map and turn action stay fixed across panels at $variant', (
      tester,
    ) async {
      await display(tester, variant.$1, tableWithSupplies(), scale: variant.$2);
      final originalMap = tester.getRect(find.byType(InteractiveViewer));
      final originalTurn = tester.getRect(find.text('End turn'));
      expect(tester.takeException(), isNull);
      for (final tab in ['Trade', 'Cards', 'Realm', 'Build']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(InteractiveViewer)), originalMap);
        expect(tester.getRect(find.text('End turn')), originalTurn);
        expect(
          tester.takeException(),
          isNull,
          reason: '$tab panel at $variant',
        );
      }
    });
  }

  testWidgets('target list dispatches the selected junction after map zoom', (
    tester,
  ) async {
    final state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 804);
    MatchEvent? event;
    await display(
      tester,
      const Size(844, 390),
      state,
      onEvent: (value) => event = value,
    );
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    await tester.tap(find.byTooltip('Choose board target from list'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(event, isA<PlaceVillage>());
    final updated = MatchEngine.apply(state, event!);
    expect(
      updated.sites[MatchEngine.legalVertices(state).first]?.owner,
      state.active,
    );
    expect(updated.phase, MatchPhase.setupRoad);
  });

  testWidgets(
    'watching computer moves conceals hands and blocks board actions',
    (tester) async {
      final state = MatchEngine.newGame([
        'Ada',
        'Computer 1',
        'Computer 2',
      ], 804);
      final events = <MatchEvent>[];
      await display(
        tester,
        const Size(844, 390),
        state,
        observing: true,
        onEvent: events.add,
      );
      expect(find.text('Computer turn'), findsOneWidget);
      expect(find.text('Private hands are concealed'), findsOneWidget);
      expect(find.text('Build'), findsNothing);
      expect(find.byTooltip('Choose board target from list'), findsNothing);
      final map = find.byType(InteractiveViewer);
      final point = BoardGeometry(
        tester.getSize(map),
      ).vertex(state.topology.vertices[MatchEngine.legalVertices(state).first]);
      await tester.tapAt(tester.getTopLeft(map) + point);
      await tester.pump();
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'compact build choices scroll while trade shortcuts and turn stay reachable',
    (tester) async {
      await display(tester, const Size(640, 320), tableWithSupplies());
      final turnTop = tester.getRect(find.text('End turn')).top;
      for (final label in ['Road', 'Village', 'Upgrade']) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(label).hitTestable(), findsOneWidget);
        expect(tester.getRect(find.text('End turn')).top, turnTop);
      }
      await tester.tap(find.text('Trade'));
      await tester.pumpAndSettle();
      for (final label in ['Bank trade', 'Player trade']) {
        expect(tester.getRect(find.text(label)).bottom, lessThan(turnTop));
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('card actions wait for the roll and pending events', (
    tester,
  ) async {
    await display(
      tester,
      const Size(844, 390),
      tableWithSupplies().copyWith(phase: MatchPhase.roll),
    );
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(
      find.text('Roll and resolve pending events before playing cards.'),
      findsOneWidget,
    );
    expect(find.textContaining('Strategy hand'), findsNothing);
    expect(find.text('Roll dice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
