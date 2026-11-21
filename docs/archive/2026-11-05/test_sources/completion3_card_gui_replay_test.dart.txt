import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

/// Exact accepted-event checkpoints from Glass's isolated Linux GUI, 5 Nov 2026.
/// The 89th event was simulated before import; event 90 was played by clicking
/// Founding Charter in the running app, then copied using the UI's Copy replay.
MatchState _checkpoint(String name) => MatchEngine.importReplay(
  File('test/fixtures/$name').readAsStringSync(),
);

void main() {
  test('live GUI card event is a deterministic legal reducer continuation', () {
    final before = _checkpoint('completion3_card_pre.json');
    final observed = _checkpoint('completion3_card_after_live_gui.json');
    final expected = MatchEngine.apply(before, const PlayStrategyCard(0));

    expect(before.events, hasLength(89));
    expect(observed.events, hasLength(90));
    expect(observed.events.last, isA<PlayStrategyCard>());
    expect(MatchEngine.snapshot(observed), MatchEngine.snapshot(expected));
    expect(
      observed.current.stores[Resource.brick],
      (before.current.stores[Resource.brick] ?? 0) + 1,
    );
    expect(
      observed.current.stores[Resource.coin],
      (before.current.stores[Resource.coin] ?? 0) + 1,
    );
    expect(observed.current.cards, isEmpty);

    final raw = jsonDecode(
      File('test/fixtures/completion3_card_after_live_gui.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect((raw['events'] as List).last['type'], 'cardPlay');
    expect(
      MatchEngine.snapshot(
        MatchEngine.importReplay(MatchEngine.exportReplay(observed)),
      ),
      MatchEngine.snapshot(observed),
    );
  });

  test('live GUI Knight interception replays with no theft', () {
    final before = _checkpoint('completion3_knight_pre.json');
    final observed = _checkpoint('completion3_knight_after_live_gui.json');
    final response = before.tactical!;
    final expected = MatchEngine.apply(
      before,
      RespondTactical(response.id, response.responder, TacticalChoice.intercept),
    );
    expect(before.events, hasLength(47));
    expect(observed.events, hasLength(48));
    expect(observed.events.last, isA<RespondTactical>());
    expect(MatchEngine.snapshot(observed), MatchEngine.snapshot(expected));
    expect(observed.tactical, isNull);
    expect(observed.players[0].stores, before.players[0].stores);
    final activeBefore = before.knights.values
        .where((knight) => knight.owner == 0 && knight.active)
        .length;
    final activeAfter = observed.knights.values
        .where((knight) => knight.owner == 0 && knight.active)
        .length;
    expect(activeAfter, activeBefore - 1);
  });

  testWidgets('392px card sheet exposes legal choice and resolves once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(392, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = _checkpoint('completion3_card_pre.json');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => MatchView(
              state: state,
              onEvent: (event) => refresh(() {
                state = MatchEngine.apply(state, event);
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Founding Charter'), 300);
    await tester.tap(find.text('Founding Charter'));
    await tester.pumpAndSettle();
    expect(find.text('Play selected card'), findsOneWidget);
    await tester.tap(find.text('Collect listed supplies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play selected card'));
    await tester.pumpAndSettle();
    expect(state.events, hasLength(90));
    expect(state.events.last, isA<PlayStrategyCard>());
    expect(state.current.cards, isEmpty);
    expect(
      MatchEngine.snapshot(state),
      MatchEngine.snapshot(_checkpoint('completion3_card_after_live_gui.json')),
    );
  });
}
