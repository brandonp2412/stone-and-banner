import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/trade_picker.dart';

void main() {
  testWidgets(
    'offer quantities cap at holdings and cannot request offered goods',
    (tester) async {
      var gives = <Resource, int>{};
      var wants = <Resource, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => TradePicker(
                holdings: const {Resource.wood: 2},
                gives: gives,
                wants: wants,
                onChange: (good, giving, delta) => update(() {
                  final next = Map<Resource, int>.of(giving ? gives : wants);
                  final count = (next[good] ?? 0) + delta;
                  if (count == 0) {
                    next.remove(good);
                  } else {
                    next[good] = count;
                  }
                  if (giving) {
                    gives = next;
                  } else {
                    wants = next;
                  }
                }),
              ),
            ),
          ),
        ),
      );
      final giveWood = find.byKey(const ValueKey('trade-give-wood'));
      final getWood = find.byKey(const ValueKey('trade-get-wood'));
      await tester.tap(giveWood);
      await tester.pump();
      await tester.tap(giveWood);
      await tester.pump();
      expect(gives, {Resource.wood: 2});
      expect(tester.widget<InkWell>(giveWood).onTap, isNull);
      expect(tester.widget<InkWell>(getWood).onTap, isNull);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('trade-give-minus-wood')));
        await tester.pump();
      }
      expect(gives, isEmpty);
      await tester.tap(getWood);
      await tester.pump();
      expect(wants, {Resource.wood: 1});
      expect(tester.widget<InkWell>(giveWood).onTap, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
