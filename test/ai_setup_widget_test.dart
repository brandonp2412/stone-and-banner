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
    tester.view.physicalSize = const Size(844, 390);
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
    expect(find.textContaining('1 human · 2 computers'), findsOneWidget);
    await tester.tap(find.text('1 AI'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 humans · 1 computer'), findsOneWidget);

    await tester.ensureVisible(find.text('Player names'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2)); // two human names

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
    expect(match.players.take(2).map((p) => p.id), ['Player 1', 'Player 2']);
    expect(match.players.last.id, isNot(startsWith('Computer')));
  });

  testWidgets(
    'four seats permit three AI and named solo human goes straight to board',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('New local match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vs AI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('4 players'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 players'));
      await tester.pumpAndSettle();
      expect(find.text('3 AI'), findsOneWidget);
      await tester.ensureVisible(find.text('3 AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 AI'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 human · 3 computer'), findsOneWidget);

      await tester.ensureVisible(find.text('Player names'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget); // one human name
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
      expect(match.players.first.id, 'Presley');
      expect(match.players.map((p) => p.id).toSet(), hasLength(4));
      expect(match.players.skip(1).every((p) => !p.id.startsWith('Computer')), isTrue);
    },
  );

  testWidgets('saved-match start action fits one line on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
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
    await tester.binding.handlePopRoute();
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
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    expect(find.text('New local match'), findsOneWidget);
    expect(find.text('Hot-seat'), findsNothing);
    await tester.ensureVisible(find.text('Learn the rules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn the rules'));
    await tester.pumpAndSettle();
    expect(find.text('The essentials'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Glossary'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Glossary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Glossary'));
    await tester.pumpAndSettle();
    expect(find.text('Basic goods'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Advanced play'),
      -160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Advanced play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced play'));
    await tester.pumpAndSettle();
    expect(find.text('Town Developments'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Home').first);
    await tester.pumpAndSettle();
    expect(find.text('New local match'), findsOneWidget);
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    expect(find.text('Match setup'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Home').first);
    await tester.pumpAndSettle();
    expect(find.text('New local match'), findsOneWidget);
  });

  testWidgets('blank name never leaves automatically seeded setup', (
    tester,
  ) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New local match'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Player names'));
    await tester.pumpAndSettle();
    expect(find.text('World seed'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Player 1'), ' ');
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name for each human player.'), findsOneWidget);
    expect(find.text('Start match'), findsOneWidget);
    expect(find.text('Pass the device'), findsNothing);
  });
}
