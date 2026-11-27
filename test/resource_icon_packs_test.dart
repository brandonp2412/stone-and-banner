import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

void main() {
  test('missing and unknown saved packs fall back to Tabletop', () async {
    for (final saved in [null, 'unknown']) {
      SharedPreferences.setMockInitialValues({'resource_icon_pack': ?saved});
      resourceIconStyle.value = ResourceIconStyle.treasury;
      await restoreResourceIconStyle();
      expect(resourceIconStyle.value, ResourceIconStyle.tabletop);
    }
  });

  test('every saved pack is restored, including legacy selections', () async {
    for (final style in ResourceIconStyle.values) {
      SharedPreferences.setMockInitialValues({
        'resource_icon_pack': style.name,
      });
      await restoreResourceIconStyle();
      expect(resourceIconStyle.value, style);
    }
    resourceIconStyle.value = ResourceIconStyle.banner;
  });

  testWidgets('startup decodes only the requested icon pack', (tester) async {
    final revision = resourceIconsRevision.value;
    await tester.runAsync(() async {
      final first = loadResourceIconPack(ResourceIconStyle.tabletop);
      final second = loadResourceIconPack(ResourceIconStyle.tabletop);
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
    });
    expect(resourceIconsRevision.value, revision + 1);
  });

  testWidgets('all packs load and selection persists', (tester) async {
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
    expect(
      find.byType(ResourceIcon),
      findsNWidgets(ResourceIconStyle.values.length * Resource.values.length),
    );
    for (final style in ResourceIconStyle.values) {
      await tester.ensureVisible(find.text(style.label));
      await tester.tap(find.text(style.label));
      await tester.pump();
      // The first frame after selecting a pack must have decoded images ready.
      final images = tester.widgetList<RawImage>(find.byType(RawImage));
      expect(
        images,
        hasLength(ResourceIconStyle.values.length * Resource.values.length),
      );
      expect(images.every((image) => image.image != null), isTrue);
      await tester.pumpAndSettle();
      expect(resourceIconStyle.value, style);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('resource_icon_pack'), style.name);
      expect(tester.takeException(), isNull);
    }
    expect(Resource.values.length, 8);
    resourceIconStyle.value = ResourceIconStyle.banner;
    await restoreResourceIconStyle();
    expect(resourceIconStyle.value, ResourceIconStyle.values.last);
    resourceIconStyle.value = ResourceIconStyle.banner;
  });
}
