import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('desktop board hover explains an action without taking it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = tableWithSupplies();
    var events = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(state: state, onEvent: (_) => events++),
      ),
    );
    await tester.pumpAndSettle();
    final map = find.byKey(const ValueKey('realm-map'));
    final geometry = BoardGeometry(tester.getSize(map));
    final edge = state.topology.edges[MatchEngine.legalEdges(state).first];
    final position =
        tester.getTopLeft(map) +
        (geometry.vertex(state.topology.vertices[edge.a]) +
                geometry.vertex(state.topology.vertices[edge.b])) /
            2;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(position);
    await tester.pump();
    expect(find.byKey(const ValueKey('board-hover-hint')), findsOneWidget);
    expect(find.textContaining('Build road ·'), findsWidgets);
    expect(events, 0);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('board-hover-hint')), findsNothing);
    await mouse.removePointer();
  });
}
