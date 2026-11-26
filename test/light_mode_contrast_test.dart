import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/dice_roll.dart';
import 'package:stone_and_banner/ui/game_colors.dart';
import 'package:stone_and_banner/ui/match_screen.dart'
    show MatchView, seatColors;
import 'package:stone_and_banner/ui/trade_leg.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  const surfaces = [
    Color(0xff101e25),
    Color(0xff182a31),
    Color(0xff20343c),
    Color(0xff153e36),
    Color(0xff584322),
    Color(0xff2e181c),
    Color(0xff3b304e),
  ];
  const inks = [
    Colors.white,
    Color(0xffabbfc2),
    Color(0xffe5c183),
    Color(0xff73d9c0),
    Color(0xffff977f),
    Color(0xffa7c8ff),
    Color(0xffcba4f6),
  ];
  testWidgets('light panel inks and player labels meet 4.5:1', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            for (final surface in surfaces) {
              final background = gameColor(context, surface);
              for (final ink in [...inks, ...seatColors]) {
                final foreground = gameColor(context, ink);
                expect(
                  contrast(foreground, background),
                  greaterThanOrEqualTo(4.5),
                  reason: '$ink on $surface becomes $foreground on $background',
                );
              }
              expect(
                contrast(
                  gameColor(context, const Color(0xff40565b)),
                  background,
                ),
                greaterThanOrEqualTo(3),
                reason: 'Panel outlines remain visible',
              );
            }
            // Primary actions use a light ink on a dark gold fill in light mode.
            expect(
              contrast(
                gameColor(context, const Color(0xff28271e)),
                gameColor(context, const Color(0xffe5c183)),
              ),
              greaterThanOrEqualTo(4.5),
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });
  testWidgets(
    'selected resource labels and outlines contrast with the chip fill',
    (tester) async {
      for (final highlight in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TradeLeg(
                title: 'Goods',
                hint: 'Select a good',
                resource: Resource.values.first,
                count: 1,
                onResource: (_) {},
                onCount: (_) {},
                showCount: false,
                highlight: highlight,
              ),
            ),
          ),
        );
        final chipFinder = find.byWidgetPredicate(
          (widget) => widget is ChoiceChip && widget.selected,
        );
        final chip = tester.widget<ChoiceChip>(chipFinder);
        final panel = gameColor(
          tester.element(chipFinder),
          const Color(0xff1e343d),
        );
        final fill = Color.alphaBlend(chip.selectedColor!, panel);
        expect(
          contrast(chip.labelStyle!.color!, fill),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(chip.side!.color, fill), greaterThanOrEqualTo(3));
      }
    },
  );

  testWidgets('the disabled turn action remains legible while observing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: tableWithSupplies(),
            onEvent: (_) {},
            observing: true,
          ),
        ),
      ),
    );
    final action = tester.widget<FilledButton>(
      find.ancestor(
        of: find.byIcon(Icons.check_circle_outline),
        matching: find.byType(FilledButton),
      ),
    );
    expect(action.onPressed, isNull);
    const disabled = {WidgetState.disabled};
    expect(
      contrast(
        action.style!.foregroundColor!.resolve(disabled)!,
        action.style!.backgroundColor!.resolve(disabled)!,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('dice text has an opaque high-contrast backdrop over the board', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: DiceRoll(first: 3, second: 4, onComplete: () {}),
        ),
      ),
    );
    final label = find.text('Rolling…');
    final text = tester.widget<Text>(label);
    final plaque = tester.widget<Container>(
      find.ancestor(of: label, matching: find.byType(Container)).first,
    );
    final fill = (plaque.decoration! as BoxDecoration).color!;
    expect(fill.a, 1);
    expect(contrast(text.style!.color!, fill), greaterThanOrEqualTo(4.5));
  });

  testWidgets('dark palette and translucent colors remain unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) {
            for (final color in [
              ...surfaces,
              ...inks,
              ...seatColors,
              const Color(0xf0182a31),
            ]) {
              expect(gameColor(context, color), color);
            }
            return const SizedBox();
          },
        ),
      ),
    );
  });
  testWidgets('light translucent panels preserve opacity', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              gameColor(context, const Color(0xf0182a31)).a,
              const Color(0xf0182a31).a,
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
