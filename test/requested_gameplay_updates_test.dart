import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/board.dart';

import 'resource_discard_test.dart' show seven;
import 'trade_bundle_test.dart' show stocked;

void main() {
  testWidgets('settings persist appearance and background preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Computer action delay'), findsOneWidget);
    final appearance = tester.widget<DropdownButton<ThemeMode>>(
      find.byType(DropdownButton<ThemeMode>),
    );
    appearance.onChanged!(ThemeMode.light);
    await tester.pumpAndSettle();
    final background = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Pause offline games in background'),
    );
    background.onChanged!(false);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('themeMode'), 'light');
    expect(prefs.getBool('pauseInBackground'), false);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('a target can counter during the proposer turn', () {
    var state = MatchEngine.apply(
      stocked(),
      const ProposeTrade(1, Resource.ore, 1, Resource.wood, 1),
    );
    final original = state.offers.single;
    state = MatchEngine.apply(
      state,
      ProposeTrade(
        0,
        Resource.wood,
        2,
        Resource.ore,
        1,
        counterOf: original.id,
      ),
    );
    expect(state.active, 0);
    expect(state.offers.single.proposer, 1);
    expect(state.offers.single.isCounter, isTrue);
    state = MatchEngine.apply(
      state,
      RespondTrade(0, true, offerId: state.offers.single.id),
    );
    expect(state.offers, isEmpty);
    expect(state.players[0].stores[Resource.wood], 2);
  });

  test('idle discard selects a valid hand and returns goods to bank', () {
    var state = seven();
    final dice = MatchEngine.expectedDice(state);
    state = MatchEngine.apply(state, RollDice(dice.$1, dice.$2));
    final before = state.players[0].stores.values.fold<int>(0, (a, b) => a + b);
    final required = state.pendingDiscards[0]!;
    final idle = MatchEngine.idleEvent(state);
    expect(idle, isA<DiscardResources>());
    state = MatchEngine.apply(state, idle!);
    expect(state.pendingDiscards, isEmpty);
    expect(
      state.players[0].stores.values.fold<int>(0, (a, b) => a + b),
      before - required,
    );
  });
}
