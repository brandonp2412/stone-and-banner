import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  testWidgets('local game and LAN room remain separate entry paths', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const StoneBannerApp());
    await tester.pumpAndSettle();
    expect(find.text('Start match'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('LAN multiplayer room'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('LAN multiplayer room'));
    await tester.pumpAndSettle();
    expect(find.text('Create LAN room'), findsOneWidget);
    expect(find.text('Join room'), findsOneWidget);
    expect(find.text('Host WebSocket URL'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Start match'), findsOneWidget);
  });
}
