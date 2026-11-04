import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> startAi(WidgetTester tester) async {
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vs AI'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('2 AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 AI'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(find.text('Pass the device'), findsNothing);
  }

  Future<void> humanSetup(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.text('Choose board target from list'));
      await tester.tap(find.text('Choose board target from list'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pump();
    }
    expect(find.text('Computer turn'), findsOneWidget);
    expect(find.text('Your goods'), findsNothing);
  }

  Future<Map<String, dynamic>> saved() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString('stone_banner_local_session_v2')!)
        as Map<String, dynamic>;
  }

  Future<void> finishAi(WidgetTester tester) async {
    for (var tick = 0; tick < 100; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
      final session = await saved();
      final state = MatchEngine.importReplay(session['replay'] as String);
      if ((state.tactical?.responder ?? state.active) == 0 &&
          find.text('Computer turn').evaluate().isEmpty) {
        return;
      }
    }
    fail('Computer did not return to human seat within 10 simulated seconds');
  }

  testWidgets('computer setup is private, completes a turn, and resumes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await startAi(tester);
    await humanSetup(tester);
    await finishAi(tester);
    final session = await saved();
    expect(session['computerSeats'], [1, 2]);
    final snapshot = MatchEngine.importReplay(session['replay'] as String);
    expect((snapshot.tactical?.responder ?? snapshot.active), 0);
    expect(snapshot.events.length, greaterThanOrEqualTo(4));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue saved match'));
    await tester.pumpAndSettle();
    expect(find.text('Computer turn'), findsNothing);
    expect(find.text('Pass the device'), findsNothing);
    expect(find.text('Choose board target from list'), findsOneWidget);
  });

  testWidgets('leaving board cancels an in-flight bot event', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await startAi(tester);
    await humanSetup(tester);
    final before = await saved();
    final eventCount =
        MatchEngine.importReplay(before['replay'] as String).events.length;
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final after = await saved();
    expect(MatchEngine.importReplay(after['replay'] as String).events.length,
        eventCount);
    await tester.tap(find.byIcon(Icons.hexagon_outlined));
    await tester.pump();
    expect(find.text('Computer turn'), findsOneWidget);
    await finishAi(tester);
    expect(find.text('Computer turn'), findsNothing);
  });
}
