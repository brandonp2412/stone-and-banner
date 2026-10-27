import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';

void main() {
  test('structure values and 15-point victory', () {
    expect(
      GameEngine.score(PlayerState(id: 'Ada', buildings: Structure.values)),
      7,
    );
    final state = GameState(
      players: [
        PlayerState(id: 'Ada', charterPoints: 15),
        PlayerState(id: 'Ben'),
      ],
    );
    expect(GameEngine.winner(state), 'Ada');
    expect(() => GameEngine.advanceTurn(state), throwsStateError);
  });

  test('round boundary advances season and replenishes reactions', () {
    var state = GameEngine.newGame(['Ada', 'Ben']);
    state = GameEngine.openReactionWindow(state, WindowType.invasion);
    state = GameEngine.react(state, 'Ben', Reaction.escort);
    expect(state.players[1].reactionTokens, 0);
    expect(
      () => GameEngine.react(state, 'Ben', Reaction.escort),
      throwsStateError,
    );
    state = GameEngine.closeReactionWindow(state);
    for (var i = 0; i < 6; i++) {
      state = GameEngine.advanceTurn(state);
    }
    expect(state.round, 4);
    expect(state.season, Season.bloom);
    expect(state.reaverPressure, 3);
    expect(state.players[1].reactionTokens, 1);
  });

  test('catchup 3:1 trades real resources at most once per round', () {
    var state = GameState(
      activePlayerIndex: 1,
      players: [
        PlayerState(id: 'Ada', buildings: [Structure.capital]),
        PlayerState(id: 'Ben', stores: {Resource.wood: 7}),
      ],
    );
    expect(GameEngine.bankTradeRate(state, 'Ben'), 3);
    state = GameEngine.bankTrade(state, 'Ben', Resource.wood, Resource.wheat);
    expect(state.players[1].stores[Resource.wood], 4);
    expect(state.players[1].stores[Resource.wheat], 1);
    expect(GameEngine.score(state.players[1]), 0);
    expect(GameEngine.bankTradeRate(state, 'Ben'), 4);
    state = GameEngine.bankTrade(state, 'Ben', Resource.wood, Resource.ore);
    expect(state.players[1].stores[Resource.wood], 0);
    expect(
      () => GameEngine.bankTrade(state, 'Ben', Resource.ore, Resource.wheat),
      throwsStateError,
    );
    expect(
      () => GameEngine.bankTrade(state, 'Ben', Resource.wheat, Resource.paper),
      throwsStateError,
    );
  });

  test('reject invalid seats, windows and reaction types', () {
    final state = GameEngine.newGame(['Ada', 'Ben']);
    expect(GameEngine.winner(state), isNull);
    expect(() => GameEngine.newGame(['Ada', 'Ada']), throwsStateError);
    final open = GameEngine.openReactionWindow(state, WindowType.caravan);
    expect(() => GameEngine.advanceTurn(open), throwsStateError);
    expect(
      () => GameEngine.react(open, 'Ada', Reaction.offer),
      throwsStateError,
    );
    expect(
      () => GameEngine.react(open, 'Ben', Reaction.blockade),
      throwsStateError,
    );
    expect(
      () => GameEngine.react(open, 'Nobody', Reaction.offer),
      throwsStateError,
    );
  });
}
