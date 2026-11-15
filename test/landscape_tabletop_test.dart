import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

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
  testWidgets('compact primary build and trade choices fit without scrolling', (
    tester,
  ) async {
    await display(tester, const Size(640, 320), tableWithSupplies());
    final turnTop = tester.getRect(find.text('End turn')).top;
    for (final label in ['Road', 'Village', 'Upgrade']) {
      expect(tester.getRect(find.text(label)).bottom, lessThan(turnTop));
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    await tester.tap(find.text('Trade'));
    await tester.pumpAndSettle();
    for (final label in ['Bank trade', 'Player trade']) {
      expect(tester.getRect(find.text(label)).bottom, lessThan(turnTop));
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

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
