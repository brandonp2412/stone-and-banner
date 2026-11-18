import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

void main() {
  testWidgets('all five complete packs load and selection persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(loadResourceIcons);
    expect(resourceIconsRevision.value, greaterThan(0));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showResourceIconPicker(context),
              child: const Text('Choose icons'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose icons'));
    await tester.pumpAndSettle();
    expect(find.byType(ResourceIcon), findsNWidgets(40));
    for (final style in ResourceIconStyle.values) {
      await tester.ensureVisible(find.text(style.label));
      await tester.tap(find.text(style.label));
      await tester.pump();
      // The first frame after selecting a pack must have decoded images ready.
      final images = tester.widgetList<RawImage>(find.byType(RawImage));
      expect(images, hasLength(40));
      expect(images.every((image) => image.image != null), isTrue);
      await tester.pumpAndSettle();
      expect(resourceIconStyle.value, style);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('resource_icon_pack'), style.name);
      expect(tester.takeException(), isNull);
    }
    expect(Resource.values.length, 8);
    resourceIconStyle.value = ResourceIconStyle.gameIcons;
    await restoreResourceIconStyle();
    expect(resourceIconStyle.value, ResourceIconStyle.twemoji);
    resourceIconStyle.value = ResourceIconStyle.gameIcons;
  });
}
