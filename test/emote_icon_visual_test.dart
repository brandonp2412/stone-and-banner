import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/emote_icon.dart';

void main() {
  testWidgets(
    'custom emotes retain a matching palette at small and large sizes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 180);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ColoredBox(
            color: const Color(0xff101e25),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final size in [96.0, 24.0])
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final face in ['😄', '😏', '😈'])
                        GameEmoteIcon(face, size: size),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Laughing face',
        'Cheeky face',
        'Cheeky devil emoji',
      ]) {
        expect(find.bySemanticsLabel(label), findsNWidgets(2));
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/emote_faces.png'),
      );
    },
  );
}
