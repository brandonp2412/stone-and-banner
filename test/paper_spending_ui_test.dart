import 'resource_label_finder.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('paper spends on the next Innovation town development', (
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
    final woodland = state.board.tiles.indexWhere(
      (hex) => hex.land == Land.woodland,
    );
    final vertex = state.topology.tileVertices[woodland].first;
    final sites = {...state.sites, vertex: Site(state.active, Structure.town)};
    final players = state.players.toList();
    players[state.active] = state.current.copyWith(
      developments: {StrategyDeck.innovation: 1},
    );
    state = state.copyWith(sites: sites, players: players);
    final before = state.current.stores[Resource.paper] ?? 0;
    expect(MatchEngine.canDevelop(state, StrategyDeck.innovation), isTrue);
    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) {
              refresh = update;
              return MatchView(
                state: state,
                onEvent: (event) =>
                    refresh(() => state = MatchEngine.apply(state, event)),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Realm'));
    await tester.pumpAndSettle();
    expect(resourceLabel('$before paper', contains: true), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/realm_developments.png'),
    );
    expect(find.text('Spend paper on Innovation'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('quick-innovation-development')),
    );
    await tester.pumpAndSettle();
    expect(state.current.level(StrategyDeck.innovation), 2);
    expect(state.current.stores[Resource.paper], before - 1);
    expect(tester.takeException(), isNull);
  });
}
