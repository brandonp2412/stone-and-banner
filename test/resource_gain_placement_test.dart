import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('harvest gains remain readable above the resource tray', (
    tester,
  ) async {
    await tester.runAsync(loadResourceIcons);
    await (FontLoader(
      'NotoSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = tableWithSupplies();
    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) {
              refresh = update;
              return MatchView(state: state, onEvent: (_) {});
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final players = state.players.toList();
    final hand = Map<Resource, int>.of(players[state.active].stores);
    hand[Resource.wood] = (hand[Resource.wood] ?? 0) + 2;
    hand[Resource.wheat] = (hand[Resource.wheat] ?? 0) + 1;
    players[state.active] = players[state.active].copyWith(stores: hand);
    refresh(
      () => state = state.copyWith(
        rollCount: state.rollCount + 1,
        players: players,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final wood = find.byKey(const ValueKey('resource-gain-wood'));
    expect(wood, findsOneWidget);
    final tile = find.byKey(const ValueKey('resource-tile-wood'));
    expect(tester.getCenter(wood).dx, closeTo(tester.getCenter(tile).dx, 1));
    expect(tester.getRect(wood).bottom, lessThan(tester.getRect(tile).top));
    final wheat = find.byKey(const ValueKey('resource-gain-wheat'));
    final wheatTile = find.byKey(const ValueKey('resource-tile-wheat'));
    expect(
      tester.getCenter(wheat).dx,
      closeTo(tester.getCenter(wheatTile).dx, 1),
    );
    final y = tester.getRect(wood).top;
    expect(y, greaterThan(230));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(wood, findsOneWidget);
    expect(tester.getCenter(wood).dx, closeTo(tester.getCenter(tile).dx, 1));
    expect(tester.getRect(wood).bottom, lessThan(tester.getRect(tile).top));
    await tester.pump(const Duration(milliseconds: 1700));
    expect(wood, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
