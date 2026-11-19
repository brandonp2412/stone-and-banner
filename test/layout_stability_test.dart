import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/invasion_meter.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  for (final size in [
    const Size(1440, 1000),
    const Size(960, 720),
    const Size(430, 900),
  ]) {
    testWidgets('turn and inventory updates preserve layout at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'gameplay_hints_enabled': false});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = tableWithSupplies();
      Future<void> show(MatchState state, {bool observing = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MatchView(
                state: state,
                observing: observing,
                online: true,
                viewingSeat: 0,
                onEvent: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(original);
      final map = tester.getRect(find.byKey(const ValueKey('realm-map')));
      final fleet = tester.getRect(find.byType(InvasionMeter));
      if (size.width < 900) {
        await tester.tap(find.byKey(const ValueKey('mobile-open-actions')));
        await tester.pumpAndSettle();
      }
      const labels = ['Road', 'Village', 'Upgrade', 'Fortify'];
      Map<String, Rect> actions() => {
        for (final label in labels)
          label: tester.getRect(find.widgetWithText(OutlinedButton, label)),
      };
      final initial = actions();
      final players = original.players
          .map(
            (p) => p.copyWith(
              stores: {for (final good in Resource.values) good: 0},
            ),
          )
          .toList();
      for (final state in [
        original.copyWith(players: players),
        original.copyWith(reaverScars: original.sites.keys.toSet()),
        original.copyWith(phase: MatchPhase.roll),
        original.copyWith(active: 1),
      ]) {
        await show(state, observing: state.active != 0);
        expect(actions(), initial);
        expect(tester.takeException(), isNull);
      }
      if (size.width < 900) {
        await tester.tap(find.byTooltip('Back to map'));
        await tester.pumpAndSettle();
      }
      await show(original.copyWith(reaverPressure: 2));
      expect(tester.getRect(find.byKey(const ValueKey('realm-map'))), map);
      expect(tester.getRect(find.byType(InvasionMeter)), fleet);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
