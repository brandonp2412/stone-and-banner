import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/main.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('three seats allow exactly one AI and preserve hot-seat', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();

    expect(find.text('Hot-seat'), findsOneWidget);
    expect(find.text('Vs AI'), findsOneWidget);
    expect(find.text('Computer opponents'), findsNothing);
    await tester.tap(find.text('Vs AI'));
    await tester.pumpAndSettle();
    expect(find.text('1 AI'), findsOneWidget);
    expect(find.text('2 AI'), findsOneWidget);
    expect(find.text('3 AI'), findsNothing);
    expect(find.textContaining('2 humans · 1 computer'), findsOneWidget);

    await tester.tap(find.text('Player names'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3)); // two humans + seed

    await tester.ensureVisible(find.text('Start match'));
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final session = jsonDecode(
      prefs.getString('stone_banner_local_session_v2')!,
    ) as Map<String, dynamic>;
    expect(session['computerSeats'], [2]);
    final match = MatchEngine.importReplay(session['replay'] as String);
    expect(match.players.map((p) => p.id).toList(), [
      'Player 1',
      'Player 2',
      'Computer 1',
    ]);
  });

  testWidgets(
    'four seats permit three AI and named solo human goes straight to board',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('New local match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vs AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 players'));
      await tester.pumpAndSettle();
      expect(find.text('3 AI'), findsOneWidget);
      await tester.tap(find.text('3 AI'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 human · 3 computer'), findsOneWidget);

      await tester.tap(find.text('Player names'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2)); // one human + seed
      await tester.enterText(
        find.widgetWithText(TextField, 'Player 1'),
        'Presley',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Start match'));
      await tester.tap(find.text('Start match'));
      await tester.pumpAndSettle();
      expect(find.text('Pass the device'), findsNothing);
      expect(find.byType(MatchView), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      final session = jsonDecode(
        prefs.getString('stone_banner_local_session_v2')!,
      ) as Map<String, dynamic>;
      expect(session['computerSeats'], [1, 2, 3]);
      final match = MatchEngine.importReplay(session['replay'] as String);
      expect(match.players.map((p) => p.id).toList(), [
        'Presley',
        'Computer 1',
        'Computer 2',
        'Computer 3',
      ]);
    },
  );

  testWidgets('saved-match start action fits one line on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final replay = MatchEngine.exportReplay(
      MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 20261027),
    );
    SharedPreferences.setMockInitialValues({
      'stone_banner_local_replay_v1': replay,
    });
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    expect(find.text('Start new match'), findsOneWidget);
    expect(find.text('Replaces your saved match'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Start new match');
    expect(tester.getSize(button).height, lessThan(60));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Replace saved match?'), findsOneWidget);
    await tester.tap(find.text('Keep saved match'));
    await tester.pumpAndSettle();
    expect(find.text('Match setup'), findsOneWidget);
    expect(find.text('Pass the device'), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start new match').last);
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);
  });

  testWidgets('hot-seat remains all human with private first turn', (
    tester,
  ) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Start match'));
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final session = jsonDecode(
      prefs.getString('stone_banner_local_session_v2')!,
    ) as Map<String, dynamic>;
    expect(session['computerSeats'], isEmpty);
  });

  testWidgets('home keeps rules, glossary, setup and back navigation focused', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    expect(find.text('New local match'), findsOneWidget);
    expect(find.text('Hot-seat'), findsNothing);
    await tester.tap(find.text('Learn the rules'));
    await tester.pumpAndSettle();
    expect(find.text('The essentials'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Glossary'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Glossary'));
    await tester.pumpAndSettle();
    expect(find.text('Basic goods'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Advanced play'),
      -160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Advanced play'));
    await tester.pumpAndSettle();
    expect(find.text('Town Developments'), findsOneWidget);
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('New local match'), findsOneWidget);
    await tester.tap(find.text('Board').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create a match'));
    await tester.pumpAndSettle();
    expect(find.text('Match setup'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Home'));
    await tester.pumpAndSettle();
    expect(find.text('New local match'), findsOneWidget);
  });

  testWidgets('invalid seed and blank name never leave setup', (tester) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Player names'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'World seed'), 'abc');
    await tester.ensureVisible(find.text('Start match'));
    await tester.tap(find.text('Start match'));
    await tester.pump();
    expect(find.text('Enter a numeric world seed.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'World seed'), '321');
    await tester.enterText(find.widgetWithText(TextField, 'Player 1'), ' ');
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name for each human player.'), findsOneWidget);
    expect(find.text('Start match'), findsOneWidget);
    expect(find.text('Pass the device'), findsNothing);
  });
}
