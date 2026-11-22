import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/main.dart' show StoneBannerApp;

import 'portrait_visual_audit_test.dart' show portraitSetup, golden;

Future<void> home(WidgetTester tester) async {
  await portraitSetup(tester);
  await tester.pumpWidget(const StoneBannerApp(randomizeTurnOrder: false));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('stone-home-page')), findsOneWidget);
}

void main() {
  testWidgets('portrait settings and rules remain scrollable', (tester) async {
    await home(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Gameplay hints'), findsOneWidget);
    await golden(tester, 'settings');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn the rules'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stone-rules-page')), findsOneWidget);
    await golden(tester, 'rules');
    expect(find.byTooltip('Back to Home'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Home'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stone-home-page')), findsOneWidget);
  });

  testWidgets('portrait multiplayer and LAN setup are accessible', (
    tester,
  ) async {
    await home(tester);
    await tester.tap(find.text('Host / join multiplayer'));
    await tester.pumpAndSettle();
    await golden(tester, 'p2p_setup');
    expect(find.text('Direct P2P multiplayer'), findsOneWidget);
    final advanced = find.textContaining('Advanced: native-app LAN rooms');
    expect(advanced, findsOneWidget);
    await tester.ensureVisible(advanced);
    await tester.tap(advanced);
    await tester.pumpAndSettle();
    expect(find.text('Play together on Wi-Fi'), findsOneWidget);
    await golden(tester, 'lan_setup');
    await tester.pumpWidget(const SizedBox.shrink());
    // LAN discovery uses a 400ms deferred completion; drain it after disposal.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('portrait history and replay import dialogs fit', (tester) async {
    await home(tester);
    await tester.tap(find.text('Match history'));
    await tester.pumpAndSettle();
    expect(find.text('Match history'), findsOneWidget);
    await golden(tester, 'history');
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import replay'));
    await tester.pumpAndSettle();
    expect(find.text('Paste replay JSON'), findsOneWidget);
    await golden(tester, 'import');
  });
}
