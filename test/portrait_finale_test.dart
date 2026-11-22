import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_end_modal.dart';

MatchState finaleFixture() {
  final state = MatchEngine.newGame([
    'Long named player in the southern kingdom',
    'Mira of Stonewater',
    'Briar the steadfast',
    'Rowan of the northern coast',
  ], 800).copyWith(phase: MatchPhase.finished);
  final players = state.players.toList();
  players[0] = players[0].copyWith(guardianHonour: 15);
  return state.copyWith(players: players);
}

void main() {
  testWidgets('portrait finale visual baseline', (tester) async {
    const size = Size(393, 852);
    await (FontLoader(
      'NotoSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'NotoSans',
        ),
        home: Scaffold(
          body: MatchEndModal(
            state: finaleFixture(),
            winner: 0,
            victory: true,
            onReview: () {},
            onHome: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/portrait_finale.png'),
    );
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 568),
    const Size(360, 740),
    const Size(393, 852),
    const Size(430, 932),
  ]) {
    for (final scale in [1.0, 1.6]) {
      for (final victory in [true, false]) {
        testWidgets(
          'portrait finale fits $size scale $scale victory $victory',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var reviewed = false;
            var returnedHome = false;
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(
                  useMaterial3: true,
                  brightness: Brightness.dark,
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: MatchEndModal(
                      state: finaleFixture(),
                      winner: 0,
                      victory: victory,
                      onReview: () => reviewed = true,
                      onHome: () => returnedHome = true,
                    ),
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 1200));
            final dialogRect = tester.getRect(
              find.byKey(const ValueKey('match-finale-dialog')),
            );
            final review = find.byKey(const ValueKey('match-finale-review'));
            final home = find.byKey(const ValueKey('match-finale-home'));
            for (final button in [review, home]) {
              final rect = tester.getRect(button);
              expect(
                rect.top,
                greaterThanOrEqualTo(dialogRect.top),
                reason: '$button must be inside dialog',
              );
              expect(
                rect.bottom,
                lessThanOrEqualTo(dialogRect.bottom + 1),
                reason: '$button must be visible',
              );
              expect(rect.left, greaterThanOrEqualTo(dialogRect.left));
              expect(rect.right, lessThanOrEqualTo(dialogRect.right + 1));
            }
            expect(
              find.text(
                'Long named player in the southern kingdom claims the realm',
              ),
              findsOneWidget,
            );
            expect(find.text(victory ? 'VICTORY' : 'DEFEAT'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('match-finale-portrait-scroll')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(home);
            expect(returnedHome, isTrue);
            await tester.tap(review);
            expect(reviewed, isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
