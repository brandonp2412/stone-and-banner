import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';

void main() {
  test('offer holds no goods and acceptance atomically swaps both hands', () {
    var state = MatchEngine.newGame([
      'A',
      'B',
      'C',
    ], 71).copyWith(phase: MatchPhase.actions);
    final players = state.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wood: 3});
    players[1] = players[1].copyWith(stores: {Resource.brick: 2});
    state = state.copyWith(
      players: players,
      bank: {...state.bank, Resource.wood: 16, Resource.brick: 17},
    );
    state = MatchEngine.apply(
      state,
      const ProposeTrade(1, Resource.wood, 2, Resource.brick, 1),
    );
    final id = state.offers.single.id;
    expect(state.players[0].stores[Resource.wood], 3);
    expect(state.players[1].stores[Resource.brick], 2);
    state = MatchEngine.apply(state, RespondTrade(1, true, offerId: id));
    expect(state.players[0].stores[Resource.wood], 1);
    expect(state.players[0].stores[Resource.brick], 1);
    expect(state.players[1].stores[Resource.wood], 2);
    expect(state.players[1].stores[Resource.brick], 1);
    for (final resource in Resource.values) {
      final total =
          state.bank[resource]! +
          state.players.fold<int>(
            0,
            (sum, player) => sum + (player.stores[resource] ?? 0),
          );
      expect(total, MatchEngine.bankSupply, reason: resource.name);
    }
    expect(state.offers, isEmpty);
  });

  test('declining or withdrawing an offer never refunds extra resources', () {
    var state = MatchEngine.newGame([
      'A',
      'B',
      'C',
    ], 72).copyWith(phase: MatchPhase.actions);
    final players = state.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wood: 2});
    state = state.copyWith(
      players: players,
      bank: {...state.bank, Resource.wood: 17},
    );
    final offered = MatchEngine.apply(
      state,
      const ProposeTrade(1, Resource.wood, 1, Resource.brick, 1),
    );
    final id = offered.offers.single.id;
    final declined = MatchEngine.apply(
      offered,
      RespondTrade(1, false, offerId: id),
    );
    expect(declined.players[0].stores[Resource.wood], 2);
    final withdrawn = MatchEngine.apply(offered, WithdrawTrade(id));
    expect(withdrawn.players[0].stores[Resource.wood], 2);
    final playersAfterSpend = offered.players.toList();
    playersAfterSpend[0] = playersAfterSpend[0].copyWith(stores: {});
    final unable = offered.copyWith(players: playersAfterSpend);
    expect(
      () => MatchEngine.apply(unable, RespondTrade(1, true, offerId: id)),
      throwsStateError,
    );
  });
}
