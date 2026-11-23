import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/main.dart';

void main() {
  testWidgets('setup choices and hidden player names survive app recreation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> openSetup() async {
      await tester.pumpWidget(const StoneBannerApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('New local match'));
      await tester.pumpAndSettle();
    }

    await openSetup();
    await tester.tap(find.text('4 players'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.enterText(find.byType(TextField).at(i), 'Name $i');
    }
    await tester.tap(find.text('Vs bots'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 bots'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await openSetup();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Vs bots'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '4 players'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '3 bots'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Easy'))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Hot-seat'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(
        tester.widget<TextField>(find.byType(TextField).at(i)).controller!.text,
        'Name $i',
      );
    }
    await tester.pumpWidget(const SizedBox());
    await openSetup();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Hot-seat'))
          .selected,
      isTrue,
    );
  });
}
