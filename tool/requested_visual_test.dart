import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import '../test/action_helpers.dart';
import '../test/landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  for (final size in [const Size(393, 852), const Size(844, 390)]) {
    testWidgets('inline actions at $size', (tester) async {
      final fonts = FontLoader('NotoSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      await fonts.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
          home: Scaffold(
            body: MatchView(
              state: tableWithSupplies(),
              onEvent: (_) {},
              onHome: () {},
              onRules: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Actions'));
      await tester.pumpAndSettle();
      await scrollToAction(tester, 'Knights & Defense');
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'visual_snapshots/inline_actions_${size.width.toInt()}.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('dice thrown on the board', (tester) async {
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
    var state = tableWithSupplies().copyWith(phase: MatchPhase.roll);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, refresh) => MatchView(
              state: state,
              onEvent: (e) =>
                  refresh(() => state = MatchEngine.apply(state, e)),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Roll dice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('visual_snapshots/dice_on_board.png'),
    );
    await tester.pumpAndSettle();
    expect(state.rollCount, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
