import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('Space leaves an observing match alone', (tester) async {
    SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: tableWithSupplies().copyWith(phase: MatchPhase.roll),
            observing: true,
            onEvent: events.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(events, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final phase in [
    MatchPhase.roll,
    MatchPhase.actions,
    MatchPhase.invasion,
  ]) {
    testWidgets('Space invokes the main action during ${phase.name}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
      final events = <MatchEvent>[];
      final outerFocus = FocusNode();
      addTearDown(outerFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              focusNode: outerFocus,
              autofocus: true,
              child: MatchView(
                state: tableWithSupplies().copyWith(phase: phase),
                onEvent: events.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      outerFocus.requestFocus();
      await tester.pump();
      expect(outerFocus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(events, hasLength(1));
      expect(events.single, switch (phase) {
        MatchPhase.roll => isA<RollDice>(),
        MatchPhase.actions => isA<EndTurn>(),
        _ => isA<ResolveInvasion>(),
      });
      events.clear();
      final context = tester.element(find.byType(MatchView));
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(events, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
