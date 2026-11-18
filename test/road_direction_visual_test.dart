import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

void main() {
  testWidgets(
    'new roads reveal from their connected village, not edge ID order',
    (tester) async {
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
      var state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 901);
      final vertex = MatchEngine.legalVertices(state).firstWhere(
        (v) => state.topology.vertices[v].edges.any(
          (id) => state.topology.edges[id].b == v,
        ),
      );
      state = MatchEngine.apply(state, PlaceVillage(vertex));
      final road = MatchEngine.legalEdges(state)
          .firstWhere((id) => state.topology.edges[id].b == vertex);
      final next = MatchEngine.apply(state, PlaceRoad(road));
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
      refresh(() => state = next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/road_build_from_village.png'),
      );
      await tester.pumpAndSettle();
      expect(next.roads.containsKey(road), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
