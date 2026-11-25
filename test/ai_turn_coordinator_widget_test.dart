import 'board_target_helpers.dart';
import 'p2p_trade_turn_ui_test.dart' show botOffersHuman;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );

  Future<void> startAi(WidgetTester tester) async {
    await tester.pumpWidget(const StoneBannerApp(randomizeTurnOrder: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vs bots'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('2 bots'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 bots'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsNothing);
  }

  Future<Map<String, dynamic>> saved() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString('stone_banner_local_session_v2')!)
        as Map<String, dynamic>;
  }

  Future<void> humanSetup(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      final session = await saved();
      await tapBoardTarget(
        tester,
        MatchEngine.importReplay(session['replay'] as String),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
    expect(find.text('Watch the realm grow.'), findsNothing);
    expect(find.text('Your goods'), findsNothing);
  }

  Future<void> finishAi(WidgetTester tester) async {
    for (var tick = 0; tick < 300; tick++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final session = await saved();
      final state = MatchEngine.importReplay(session['replay'] as String);
      if ((state.tactical?.responder ?? state.active) == 0 &&
          find.text('Computer turn').evaluate().isEmpty) {
        return;
      }
    }
    fail('Computer did not return to human seat within 30 simulated seconds');
  }

  testWidgets('computer setup is private, completes a turn, and resumes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await startAi(tester);
    expect(find.byKey(const ValueKey('fast-forward-bots')), findsNothing);
    await humanSetup(tester);
    final fastForward = find.byKey(const ValueKey('fast-forward-bots'));
    expect(fastForward, findsOneWidget);
    final buttonBounds = tester.getRect(fastForward);
    expect(buttonBounds.right, greaterThan(800));
    final actionsBounds = tester.getRect(
      find.byKey(const ValueKey('mobile-open-actions')),
    );
    expect(buttonBounds.center.dy, actionsBounds.center.dy);
    expect(buttonBounds.left, greaterThan(actionsBounds.right));
    await tester.tap(fastForward);
    await finishAi(tester);
    expect(fastForward, findsNothing);
    // Drain the presentation timer that fast-forward bypassed.
    await tester.pump(const Duration(seconds: 3));
    final session = await saved();
    expect(session['computerSeats'], [1, 2]);
    final snapshot = MatchEngine.importReplay(session['replay'] as String);
    expect((snapshot.tactical?.responder ?? snapshot.active), 0);
    expect(snapshot.events.length, greaterThanOrEqualTo(4));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const StoneBannerApp(randomizeTurnOrder: false));
    await tester.pumpAndSettle();
    expect(find.text('Computer turn'), findsNothing);
    expect(find.text('Pass the device'), findsNothing);
    expect(find.byTooltip('Choose target'), findsNothing);
  });

  testWidgets('desktop Space shortcut resumes a bot waiting for a trade', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await startAi(tester);
    final dynamic app = tester.state(find.byType(StoneBannerApp));
    app.ai.pause();
    final offered = botOffersHuman();
    app.setState(() {
      app.match = offered;
      app.aiSeats = <int>{1, 2};
    });
    app.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(app.ai.isPaused, isTrue);
    // Dismiss the incoming offer without answering it.
    final dismiss = find.byKey(const ValueKey('dismiss-incoming-trade'));
    if (dismiss.evaluate().isNotEmpty) {
      await tester.tap(dismiss);
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('fast-forward-bots')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(app.ai.isPaused, isFalse);
    for (var tick = 0; tick < 100 && identical(app.match, offered); tick++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(identical(app.match, offered), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('fast-forward rolls once when the sole human gets their turn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await startAi(tester);
    final dynamic app = tester.state(find.byType(StoneBannerApp));
    app.ai.pause();
    var state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 4613);
    for (var i = 0; i < 6; i++) {
      state = MatchEngine.apply(
        state,
        PlaceVillage(MatchEngine.legalVertices(state).first),
      );
      state = MatchEngine.apply(
        state,
        PlaceRoad(MatchEngine.legalEdges(state).first),
      );
    }
    state = state.copyWith(active: 2, phase: MatchPhase.actions);
    final before = state.events.length;
    app.setState(() {
      app.match = state;
      app.aiSeats = <int>{1, 2};
    });
    app.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fast-forward-bots')));
    for (var tick = 0; tick < 300; tick++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (app.match.active == 0 && app.match.phase != MatchPhase.roll) break;
    }
    final MatchState after = app.match;
    expect(after.active, 0);
    expect(after.phase, isNot(MatchPhase.roll));
    expect(after.events.skip(before).whereType<RollDice>(), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('leaving board cancels an in-flight bot event', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await startAi(tester);
    await humanSetup(tester);
    final before = await saved();
    final eventCount = MatchEngine.importReplay(before['replay'] as String)
        .events
        .length;
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final after = await saved();
    expect(
      MatchEngine.importReplay(after['replay'] as String).events.length,
      eventCount,
    );
    await tester.tap(find.text('Continue saved match'));
    await tester.pump();
    expect(find.byKey(const ValueKey('realm-map')), findsOneWidget);
    expect(find.text('Watch the realm grow.'), findsNothing);
    await finishAi(tester);
    expect(find.text('Computer turn'), findsNothing);
  });
}
