import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai_turn_coordinator.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/world_seed.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  test('world seeds are automatically generated in the supported range', () {
    final seeds = List.generate(12, (_) => randomWorldSeed());
    expect(seeds, everyElement(inInclusiveRange(1, 0x7fffffff)));
    expect(seeds.toSet().length, greaterThan(1));
  });

  testWidgets('bot cadence is independent of whether it just rolled dice', (
    tester,
  ) async {
    for (final afterRoll in [false, true]) {
      var state = tableWithSupplies();
      if (afterRoll) {
        state = state.copyWith(events: [...state.events, const RollDice(3, 4)]);
      }
      var commits = 0;
      final coordinator = AiTurnCoordinator(
        read: () => state,
        commit: (_, _) {
          commits++;
          return false; // One action is sufficient to measure timing.
        },
        isComputerSeat: (_) => true,
        delay: const Duration(milliseconds: 150),
        decide: (_) => const EndTurn(),
      );
      coordinator.resume();
      await tester.pump(const Duration(milliseconds: 149));
      expect(commits, 0, reason: 'committed too early afterRoll=$afterRoll');
      await tester.pump(const Duration(milliseconds: 1));
      expect(commits, 1, reason: 'unexpected pause afterRoll=$afterRoll');
      await coordinator.settled;
    }
  });
}
