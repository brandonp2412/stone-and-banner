import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  testWidgets(
    'Home imports a real pending reaction and hides seat until ready',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final json = File('test/fixtures/stage5_invasion_reaction.json')
          .readAsStringSync();
      final expected = MatchEngine.importReplay(json);
      expect(expected.tactical?.kind, TacticalKind.invasion);

      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Import replay'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import replay'));
      await tester.pumpAndSettle();
      expect(find.text('Paste replay JSON'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, json);
      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();
      expect(find.text('Pass the device'), findsOneWidget);
      expect(find.text('Private tactical response'), findsOneWidget);
      expect(
        find.text(expected.players[expected.tactical!.responder].id),
        findsOneWidget,
      );
      expect(find.text('Invasion emergency aid'), findsNothing);
      await tester.tap(find.text("I'm ready"));
      await tester.pumpAndSettle();
      expect(find.text('Invasion emergency aid'), findsOneWidget);
      expect(find.textContaining('Strategy hand'), findsNothing);
    },
  );

  testWidgets('new match starts without a world seed input', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Player names'));
    await tester.pumpAndSettle();
    expect(find.text('World seed'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Start match'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);
  });

  testWidgets('invalid replay never echoes pasted code or parser internals', (
    tester,
  ) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import replay'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'not_a_replay');
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    expect(
      find.text('Invalid replay code. Check the text and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('FormatException'), findsNothing);
    expect(find.textContaining('not_a_replay'), findsNothing);
  });
}
