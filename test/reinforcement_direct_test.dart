import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'portrait_visual_audit_test.dart' show portraitSetup;
import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  for (final (structure, size) in [
    (Structure.town, const Size(393, 852)),
    (Structure.capital, const Size(1440, 900)),
  ]) {
    testWidgets(
      'direct reinforcement of ${structure.name} requires confirmation',
      (tester) async {
        await portraitSetup(tester);
        tester.view.physicalSize = size;
        await tester.runAsync(loadTabletopArt);
        final base = tableWithSupplies();
        final vertex = base.sites.keys.firstWhere(
          (v) => MatchEngine.legalFort(base, v),
        );
        final state = base.copyWith(
          sites: {...base.sites, vertex: Site(base.active, structure)},
        );
        final events = <MatchEvent>[];
        Widget app(MatchState state) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'NotoSans',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xffe7bf7b),
              brightness: Brightness.dark,
              surface: const Color(0xff192529),
            ),
          ),
          home: MatchView(state: state, onEvent: events.add),
        );
        await tester.pumpWidget(app(state));
        await tester.pumpAndSettle();
        final map = find.byKey(const ValueKey('realm-map'));
        final geometry = BoardGeometry(tester.getSize(map));
        final position =
            tester.getTopLeft(map) +
            geometry.vertex(state.topology.vertices[vertex]) -
            const Offset(0, 5);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(position);
        await tester.pump();
        final hint = find.byKey(const ValueKey('board-hover-hint'));
        expect(hint, findsOneWidget);
        expect(
          find.descendant(
            of: hint,
            matching: find.textContaining('Reinforce ${structure.name}'),
          ),
          findsOneWidget,
        );
        if (structure == Structure.capital) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/reinforce_capital_hover.png'),
          );
        }
        await tester.tapAt(position);
        await tester.pumpAndSettle();
        expect(find.text('Reinforce ${structure.name}?'), findsOneWidget);
        expect(events, isEmpty);
        if (structure == Structure.town) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/reinforce_town_confirm.png'),
          );
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(events, isEmpty);
        await tester.tapAt(position);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-reinforcement')));
        await tester.pumpAndSettle();
        expect(
          events.single,
          isA<FortifyTown>().having((e) => e.vertex, 'vertex', vertex),
        );
        await tester.pumpWidget(
          app(state.copyWith(fortified: {...state.fortified, vertex})),
        );
        await tester.pumpAndSettle();
        await mouse.moveTo(position + const Offset(1, 0));
        await tester.pump();
        expect(
          find.text('Already reinforced ${structure.name}'),
          findsOneWidget,
        );
        await tester.tapAt(position);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('confirm-reinforcement')),
          findsNothing,
        );
        expect(events, hasLength(1));
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
