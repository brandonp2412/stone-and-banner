import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';
import 'package:stone_and_banner/ui/trade_leg.dart';
import 'package:stone_and_banner/engine/board.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('bank trade preselects the brick missing for a village', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = tableWithSupplies();
    final players = state.players.toList();
    players[state.active] = state.current.copyWith(
      stores: {
        for (final good in Resource.values) good: 0,
        Resource.wood: 5,
        Resource.wheat: 1,
        Resource.wool: 1,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: state.copyWith(players: players),
            onEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ResourceIcon).first);
    await tester.pumpAndSettle();
    expect(find.text('Bank exchange'), findsOneWidget);
    expect(find.text('AIM FOR'), findsNothing);
    final legs = tester.widgetList<TradeLeg>(find.byType(TradeLeg));
    expect(legs.first.resource, Resource.wood);
    expect(legs.last.resource, Resource.brick);
    expect(
      find.widgetWithText(FilledButton, 'Exchange').evaluate().single.widget,
      isA<FilledButton>().having(
        (button) => button.onPressed,
        'enabled',
        isNotNull,
      ),
    );
    await tester.tap(find.text('Player'));
    await tester.pumpAndSettle();
    expect(find.text('Standing offer'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
