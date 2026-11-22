import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

void main() {
  testWidgets('opponent activity is a readable bubble on their player card', (
    tester,
  ) async {
    await tester.runAsync(loadResourceIcons);
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
    final before = MatchEngine.newGame([
      'Alex',
      'Mira',
      'Sam',
    ], 651).copyWith(active: 1, phase: MatchPhase.actions);
    final after = before.copyWith(
      events: [
        ...before.events,
        const BankExchange(Resource.wood, Resource.ore),
      ],
    );
    Widget frame(MatchState state) => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
      home: Scaffold(
        body: MatchView(
          state: state,
          visibleSeat: 0,
          observing: true,
          onEvent: (_) {},
          computerSeats: const {1, 2},
        ),
      ),
    );
    await tester.pumpWidget(frame(before));
    await tester.pumpWidget(frame(after));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('visits the market'), findsOneWidget);
    expect(
      find.text('Mira visits the market'),
      findsNothing,
      reason: 'The profile itself identifies the actor',
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/player_avatar_action.png'),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
