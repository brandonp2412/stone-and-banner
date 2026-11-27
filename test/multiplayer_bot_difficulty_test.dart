import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/network/room_host.dart';
import 'package:stone_and_banner/ui/bot_difficulty_picker.dart';

void main() {
  test(
    'host difficulty survives checkpoint and legacy rooms default to Hard',
    () {
      final room = HostedRoom('ABCDEF12', 3, 42);
      room.join('Host');
      room.setBotDifficulty(0, BotDifficulty.medium);
      final json = room.toPrivateJson();
      expect(
        HostedRoom.fromPrivateJson(json).botDifficulty,
        BotDifficulty.medium,
      );
      json.remove('botDifficulty');
      expect(
        HostedRoom.fromPrivateJson(json).botDifficulty,
        BotDifficulty.hard,
      );
    },
  );

  testWidgets('difficulty picker selects levels and fits narrow lobby', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font = FontLoader('NotoSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      await font.load();
    });
    var difficulty = BotDifficulty.hard;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'NotoSans'),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) => BotDifficultyPicker(
                  difficulty: difficulty,
                  onChanged: (value) => setState(() => difficulty = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();
    expect(difficulty, BotDifficulty.easy);
    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    expect(difficulty, BotDifficulty.medium);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = Platform.environment['SB_DIFFICULTY_SCREENSHOT'];
      if (path != null) {
        File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
      }
      image.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BotDifficultyPicker(difficulty: difficulty)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => chip.onSelected == null),
      isTrue,
    );
  });
}
