import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/focus_hint.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'action_helpers.dart';
import 'board_target_helpers.dart';
import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fonts = FontLoader('NotoSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      await fonts.load();
    }
  });
  for (final (name, size, structure) in [
    ('desktop', const Size(1440, 900), Structure.town),
    ('landscape', const Size(780, 360), Structure.capital),
    ('portrait', const Size(360, 780), Structure.town),
  ]) {
    testWidgets('first fortification leaves $name board interactive', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'gameplay_hints_enabled': true,
        'gameplay_hints_seen_v1': ['town', 'actions'],
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = tableWithSupplies();
      final vertex = base.sites.keys.firstWhere(
        (v) => MatchEngine.legalFort(base, v),
      );
      final state = base.copyWith(
        sites: {...base.sites, vertex: Site(base.active, structure)},
      );
      final events = <MatchEvent>[];
      const captureKey = ValueKey('fortification-capture');
      if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
        await tester.runAsync(loadTabletopArt);
        await tester.runAsync(loadResourceIcons);
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamily: 'NotoSans',
            ),
            home: Scaffold(
              body: MatchView(state: state, onEvent: events.add),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (size.width < 900) {
        await tester.tap(find.text('Actions'));
        await tester.pumpAndSettle();
        await scrollToAction(tester, 'Fortify');
      } else {
        await tester.ensureVisible(find.text('Fortify'));
      }
      await tester.tap(find.text('Fortify'));
      await tester.pumpAndSettle();
      expect(find.byType(FocusHint), findsNothing);
      expect(find.byTooltip('Cancel selection'), findsOneWidget);
      expect(events, isEmpty);
      if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(captureKey),
          );
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('/tmp/stone-fortify-$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await tapBoardTarget(tester, state, vertex: vertex);
      expect(
        events.single,
        isA<FortifyTown>().having((e) => e.vertex, 'vertex', vertex),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
