import 'dart:ui' show PointerDeviceKind, ImageByteFormat;

import 'package:flutter/rendering.dart';

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
    final hud = find.byKey(const ValueKey('raid-defense-hud'));
    final hudBeforeHover = tester.widget(hud);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(position);
    await tester.pump();
    expect(find.byKey(const ValueKey('board-hover-hint')), findsOneWidget);
    expect(find.textContaining('Build road ·'), findsWidgets);
    expect(events, 0);
    // Pointer motion should not rebuild unrelated match UI.
    expect(identical(tester.widget(hud), hudBeforeHover), isTrue);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('board-hover-hint')), findsNothing);
    await mouse.removePointer();
  });

  testWidgets(
    'selected upgrade never highlights recruit-only junctions on hover',
    (tester) async {
      SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = tableWithSupplies();
      final recruit = state.topology.vertices.firstWhere(
        (v) =>
            MatchEngine.legalRecruit(state, v.id) &&
            !MatchEngine.legalUpgrades(state).contains(v.id),
      );
      const captureKey = ValueKey('capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            home: MatchView(state: state, onEvent: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upgrade'));
      await tester.pumpAndSettle();
      final map = find.byKey(const ValueKey('realm-map'));
      final position =
          tester.getTopLeft(map) +
          BoardGeometry(tester.getSize(map)).vertex(recruit);
      Future<int?> pixel() => tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
        final value = bytes!.getUint32(
          (position.dy.round() * image.width + position.dx.round()) * 4,
        );
        image.dispose();
        return value;
      });
      final before = await pixel();
      expect(before, isNotNull);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getTopLeft(map) + const Offset(10, 100));
      await tester.pump();
      expect(await pixel(), before);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
