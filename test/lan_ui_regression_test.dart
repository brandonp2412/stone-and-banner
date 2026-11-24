import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/lan_room_page.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'gameplay_hints_enabled': false,
    }),
  );

  for (final size in [const Size(1000, 800), const Size(1440, 900)]) {
    testWidgets('LAN standings and waiting footer fit at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = MatchEngine.newGame(['Alice', 'Bob', 'Mira'], 42);
      await tester.pumpWidget(
        MaterialApp(
          home: MatchView(
            state: state,
            online: true,
            viewingSeat: 1,
            observing: true,
            waitingMessage: 'Waiting for Alice…',
            onEvent: (_) {},
            onLeaveRoom: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Place your village'), findsNothing);
      expect(find.text('Waiting for Alice…'), findsWidgets);
      expect(find.text(' /15'), findsNWidgets(3));
      expect(
        tester.getRect(find.text(' /15').last).right,
        lessThanOrEqualTo(size.width - 42),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('desktop trade composer shows bottom resource rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MatchView(state: tableWithSupplies(), onEvent: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trade').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-player-offer')));
    await tester.pumpAndSettle();
    for (final good in ['wool', 'coin']) {
      final target = find.byKey(ValueKey('trade-get-$good'));
      expect(target.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(target).dy,
        lessThan(tester.getTopLeft(find.text('Send offer')).dy),
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('six-player LAN clock is readable and refreshes from host', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = MatchEngine.newGame([
      'Alice',
      'Bob',
      'Mira',
      'Oswin',
      'Tamsin',
      'Alden',
    ], 42);
    Widget view(int seconds) => MaterialApp(
      home: MatchView(
        state: state,
        online: true,
        viewingSeat: 0,
        onlineTurnSeconds: seconds,
        onEvent: (_) {},
        onLeaveRoom: () {},
      ),
    );
    await tester.pumpWidget(view(78));
    await tester.pump();
    final timer = find.text('1:18');
    expect(timer, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(timer).didExceedMaxLines,
      isFalse,
    );
    await tester.pumpWidget(view(33));
    await tester.pump();
    expect(find.text('0:33'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('LAN reconnect renders safely before welcome assigns seat', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lanHost': false,
      'lanRoom': 'TESTROOM',
      'lanToken': 'test-token',
      'lanJoinAddress': '127.0.0.1:1/TESTROOM',
    });
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: LanRoomPage()));
    await tester.pump();
    await tester.pump();
    final reconnect = find.text('Reconnect to TESTROOM');
    expect(reconnect, findsOneWidget);
    await tester.ensureVisible(reconnect);
    await tester.tap(reconnect);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Play together on Wi-Fi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
