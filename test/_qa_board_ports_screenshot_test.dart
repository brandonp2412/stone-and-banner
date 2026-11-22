import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  for (final (name, size) in [
    ('wide', const Size(1536, 709)),
    ('medium', const Size(1024, 550)),
    ('compact', const Size(844, 390)),
    ('small', const Size(640, 320)),
    ('samsung', const Size(780, 360)),
    ('portrait-s25', const Size(360, 780)),
    ('portrait-tall', const Size(393, 852)),
  ]) {
    testWidgets('Capture port labels $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fonts = FontLoader('NotoSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      await fonts.load();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamily: 'NotoSans',
            ),
            home: Scaffold(
              body: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final img = await render.toImage(pixelRatio: 1);
        try {
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/stone-proof-ports-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          img.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    });
  }
}
