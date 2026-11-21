import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_end_modal.dart';

void main() {
  testWidgets('capture finale and assert Home button', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    final state = MatchEngine.newGame(['You','Bob','Sue'], 81);
    await tester.pumpWidget(RepaintBoundary(key: boundary,child:
      MaterialApp(home: Scaffold(body:
        MatchEndModal(state: state, winner: 0, victory: true,
          onReview: () {}, onHome: () {})))));
    await tester.pump(const Duration(milliseconds: 1450));
    expect(find.byKey(const ValueKey('match-finale-home')), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('match-finale-home')));
    expect(button.onPressed, isNotNull);
    // RenderReadback runs outside Flutter's fake async clock; otherwise
    // toImage() can stall the entire test suite on teardown.
    await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await render.toImage(pixelRatio: 1);
      try {
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/stone-proof-finale.png').writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        img.dispose();
      }
    });
  });
}
