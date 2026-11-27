import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'resource_label_finder.dart';

import 'package:stone_and_banner/ui/trade_picker.dart';

import 'action_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/balance.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

MatchState drafted({MatchBalance balance = MatchBalance.baseline}) {
  var s = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 44, balance: balance);
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

Future<void> captureLayout(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('layout-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/stone-layout-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> showMatch(
  WidgetTester tester,
  MatchState initial,
  void Function(MatchState) updated,
) async {
  if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
    await tester.runAsync(loadResourceIcons);
    await tester.runAsync(loadTabletopArt);
  }
  var state = initial;
  await tester.pumpWidget(
    MaterialApp(
      theme: const bool.fromEnvironment('STONE_VISUAL_CAPTURE')
          ? ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans')
          : null,
      builder: (_, child) =>
          RepaintBoundary(key: const ValueKey('layout-capture'), child: child!),
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
  if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fonts = FontLoader('NotoSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      await fonts.load();
    });
  }

  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );
  testWidgets('wide build panel groups actions in columns', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showMatch(
      tester,
      drafted().copyWith(phase: MatchPhase.actions),
      (_) {},
    );
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    final road = tester.getRect(find.widgetWithText(OutlinedButton, 'Road'));
    final village = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Village'),
    );
    expect(road.top, closeTo(village.top, 2));
    expect(road.right, lessThan(village.left));
    await captureLayout(tester, 'build');
  });

  testWidgets('bank exchange uses focused route, conserves stock and returns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
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
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Player trade');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bank trade'));
    await tester.tap(find.text('Bank trade'));
    await tester.pumpAndSettle();
    expect(find.text('Bank exchange'), findsOneWidget);
    expect(find.byKey(const ValueKey('trade-offer-preview')), findsOneWidget);
    expect(
      find.byType(Dialog),
      findsOneWidget,
    ); // Negotiation overlays the tabletop.
    final sheep = find.byKey(const ValueKey('trade-get-wool'));
    await tester.ensureVisible(sheep);
    await tester.tap(sheep);
    await tester.pumpAndSettle();
    expect(find.text('Exchange'), findsOneWidget);
    await tester.tap(find.text('Exchange'));
    await tester.pumpAndSettle();
    expect(updated.players[0].stores[Resource.wood], woodBefore - 4);
    expect(updated.players[0].stores[Resource.wool], woolBefore + 1);
    expect(updated.bank[Resource.wood], bankWoodBefore + 4);
    expect(updated.bank[Resource.wool], bankWoolBefore - 1);
    expect(find.text('Bank exchange'), findsNothing);
  });

  testWidgets('standing offer leaves goods available on its focused route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
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
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await scrollToAction(tester, 'Player trade');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Player trade'),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Player trade'));
    await tester.pumpAndSettle();
    expect(find.text('Standing offer'), findsOneWidget);
    expect(find.text('Everyone'), findsWidgets);
    final picker = tester.widget<TradePicker>(find.byType(TradePicker));
    for (final entry in picker.gives.entries) {
      for (var i = 0; i < entry.value; i++) {
        await tester.tap(
          find.byKey(ValueKey('trade-give-minus-${entry.key.name}')),
        );
        await tester.pump();
      }
    }
    for (final entry in picker.wants.entries) {
      for (var i = 0; i < entry.value; i++) {
        await tester.tap(
          find.byKey(ValueKey('trade-get-minus-${entry.key.name}')),
        );
        await tester.pump();
      }
    }
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send offer'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('trade-give-wood')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('trade-get-wool')));
    await tester.pump();

    expect(
      find.byType(Dialog),
      findsOneWidget,
    ); // Negotiation overlays the tabletop.
    await tester.tap(find.text('Send offer'));
    await tester.pumpAndSettle();
    expect(updated.offers, hasLength(1));
    expect(updated.offers.single.give, Resource.wood);
    expect(updated.offers.single.target, -1);
    expect(updated.players[0].stores[Resource.wood], before);
    expect(find.text('Standing offer'), findsNothing);
  });

  testWidgets(
    'private Bandit response has no acting hand and resolves by touch',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
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
      final nearby = s.topology.tileVertices[tile].firstWhere(
        (vertex) => !s.sites.containsKey(vertex),
      );
      s = s.copyWith(
        builders: {...s.builders, 1},
        guards: {nearby: const GuardPiece(1, GuardRank.sentinel, true, -1)},
      );
      s = MatchEngine.apply(s, MoveBandit(tile, victim: 1));
      var updated = s;
      await showMatch(tester, s, (v) => updated = v);
      expect(find.text('Response for Ben'), findsOneWidget);
      expect(find.text('Bandit interception'), findsOneWidget);
      expect(find.textContaining('Strategy hand'), findsNothing);
      expect(find.textContaining('wood '), findsNothing);
      final intercept = tester.getRect(
        find.widgetWithText(FilledButton, 'Intercept with Guard'),
      );
      final pass = tester.getRect(find.widgetWithText(OutlinedButton, 'Pass'));
      expect(intercept.center.dy, closeTo(pass.center.dy, 2));
      expect(intercept.right, lessThan(pass.left));
      expect((intercept.left + pass.right) / 2, closeTo(422, 2));
      await captureLayout(tester, 'response');
      await tester.ensureVisible(find.text('Intercept with Guard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intercept with Guard'));
      await tester.pumpAndSettle();
      expect(updated.tactical, isNull);
      expect(updated.guards[nearby]!.active, isFalse);
      expect(find.text('Bandit interception'), findsNothing);
    },
  );

  testWidgets('invasion aid and pass buttons advance responder without stall', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var s = drafted(balance: const MatchBalance(raidAidCap: 0))
        .copyWith(phase: MatchPhase.actions, active: 2, reaverPressure: 5);
    s = grant(grant(s, 1, Resource.ore), 2, Resource.wheat);
    s = MatchEngine.apply(s, const EndTurn());
    expect(s.tactical, isNotNull);
    var updated = s;
    await showMatch(tester, s, (v) => updated = v);
    expect(find.text('Response for Ada'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pass'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Pass'));
    await tester.pumpAndSettle();
    expect(find.text('Response for Ben'), findsOneWidget);
    await tester.scrollUntilVisible(
      resourceLabel('Pledge 1 ore'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(resourceLabel('Pledge 1 ore'));
    await tester.pumpAndSettle();
    expect(updated.invasionAid, 2);
    expect(find.text('Response for Cora'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pass'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pass'));
    await tester.pumpAndSettle();
    expect(updated.tactical, isNull);
    expect(find.text('Resolve'), findsOneWidget);
    expect(find.textContaining('Defence 2 /'), findsWidgets);
    // The new raid HUD shows the combined defence, not a redundant aid toast.
    expect(updated.invasionAid, 2);
  });

  testWidgets('standing offer on another turn opens a reply modal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
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
    // Incoming trades now open immediately instead of requiring a Trade tab.
    expect(find.text('Trade offer'), findsOneWidget);
    expect(find.text('From Ada'), findsOneWidget);
    expect(find.text('Counter'), findsOneWidget);
    expect(find.text('Accept').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(updated.offers, isEmpty);
    expect(updated.players[1].stores[Resource.wood], greaterThanOrEqualTo(1));
    expect(find.text('Trade offer'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
