import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/match.dart';

void main() {
  test('legacy and unknown levels preserve the original policy', () {
    expect(BotDifficulty.parse(null), BotDifficulty.hard);
    expect(BotDifficulty.parse('unknown'), BotDifficulty.hard);
    expect(BotDifficulty.parse('easy'), BotDifficulty.easy);
    final state = MatchEngine.newGame(['A', 'B', 'C'], 31);
    expect(
      const HeuristicAi().choose(state)!.toJson(),
      const HeuristicAi(difficulty: BotDifficulty.hard).choose(state)!.toJson(),
    );
    final hard = const HeuristicAi().choose(state)! as PlaceVillage;
    for (final difficulty in [BotDifficulty.easy, BotDifficulty.medium]) {
      final bot = HeuristicAi(difficulty: difficulty);
      final choice = bot.choose(state)! as PlaceVillage;
      expect(
        bot.siteValue(state, choice.vertex),
        lessThanOrEqualTo(bot.siteValue(state, hard.vertex)),
      );
      expect(choice.vertex, isNot(hard.vertex));
    }
  });

  for (final difficulty in BotDifficulty.values) {
    test(
      '${difficulty.label} makes deterministic accepted moves across turns',
      () {
        final bot = HeuristicAi(difficulty: difficulty);
        var state = MatchEngine.newGame(['A', 'B', 'C'], 31);
        for (var i = 0; i < 350 && state.phase != MatchPhase.finished; i++) {
          final event = bot.choose(state)!;
          expect(bot.choose(state)!.toJson(), event.toJson());
          final next = MatchEngine.apply(state, event);
          expect(next.events.length, state.events.length + 1);
          state = next;
        }
        expect(state.round, greaterThan(2));
      },
    );
  }
}
