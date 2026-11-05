import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/balance.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/simulation.dart';

void main() {
  test('seat rotation keeps the same policy instances and baseline rules', () {
    const lineup = [
      BalanceBot(StrategyDeck.innovation, trade: true),
      BalanceBot(StrategyDeck.commerce, defend: true),
      BalanceBot(StrategyDeck.governance, trade: true, defend: true),
    ];
    final rotated = [lineup[1], lineup[2], lineup[0]];
    final a = BalanceSimulation.run(
      seed: 11843,
      seats: 3,
      maxRounds: 8,
      lineup: rotated,
    );
    final b = BalanceSimulation.run(
      seed: 11843,
      seats: 3,
      maxRounds: 8,
      lineup: rotated,
      balance: MatchBalance.baseline,
    );
    expect(a.bots.map((b) => b.track), rotated.map((b) => b.track));
    expect(MatchEngine.snapshot(a.state), MatchEngine.snapshot(b.state));
    expect(
      MatchEngine.snapshot(
        MatchEngine.importReplay(MatchEngine.exportReplay(a.state)),
      ),
      MatchEngine.snapshot(a.state),
    );
  });

  test('default balance simulation remains byte-identical', () {
    const seed = 11845;
    const seats = 4;
    final legacy = BalanceSimulation.run(
      seed: seed,
      seats: seats,
      maxRounds: 9,
    );
    final explicit = BalanceSimulation.run(
      seed: seed,
      seats: seats,
      maxRounds: 9,
      lineup: List.generate(seats, (i) {
        final temperament = (i + seed ~/ 3) % 3;
        return BalanceBot(
          StrategyDeck.values[(i + seed % 3) % 3],
          trade: temperament != 0,
          defend: temperament != 1,
        );
      }),
    );
    expect(
      MatchEngine.exportReplay(legacy.state),
      MatchEngine.exportReplay(explicit.state),
    );
  });

  test('mismatched lineup is rejected', () {
    expect(
      () => BalanceSimulation.run(
        seed: 11844,
        seats: 4,
        lineup: const [
          BalanceBot(StrategyDeck.commerce),
          BalanceBot(StrategyDeck.governance),
          BalanceBot(StrategyDeck.innovation),
        ],
      ),
      throwsArgumentError,
    );
  });
}
