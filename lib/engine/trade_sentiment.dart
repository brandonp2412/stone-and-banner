import 'match.dart';

/// Public trade history drives deterministic AI sentiment without new save data.
abstract final class TradeSentiment {
  static int _hash(int value) {
    value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xffffffff;
    return (value ^ (value >> 16)) & 0xffffffff;
  }

  static bool angryAtDecline(MatchState state, int responseIndex) =>
      responseIndex >= 0 &&
      responseIndex < state.events.length &&
      state.events[responseIndex] is RespondTrade &&
      !(state.events[responseIndex] as RespondTrade).accept &&
      _hash(state.board.seed ^ (responseIndex * 0x9e3779b9)) % 3 == 0;

  /// Counts angry declines by recipient for this proposer. Counters and
  /// withdrawals resolve offers without counting as a decline.
  static Map<int, int> grievances(MatchState state, int proposer) {
    var active = state.active;
    for (final event in state.events) {
      if (event is EndTurn) {
        active = (active - 1 + state.players.length) % state.players.length;
      }
    }
    final offers = <int, (int, int)>{};
    final result = <int, int>{};
    for (var i = 0; i < state.events.length; i++) {
      final event = state.events[i];
      if (event is EndTurn) {
        active = (active + 1) % state.players.length;
      } else if (event is ProposeTrade) {
        offers.remove(event.counterOf);
        offers[i] = (active, event.target);
      } else if (event is WithdrawTrade) {
        offers.remove(event.offerId);
      } else if (event is RespondTrade) {
        final id =
            event.offerId ??
            offers.keys
                .where((id) => offers[id]!.$2 == event.player)
                .firstOrNull;
        final offer = offers.remove(id);
        if (offer != null && offer.$1 == proposer && angryAtDecline(state, i)) {
          result.update(event.player, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    }
    return result;
  }

  /// One grievance skips half of future turns; repeated anger skips three
  /// quarters. A stable per-round roll prevents rerolling by taking actions.
  static bool willingToOffer(
    MatchState state,
    int proposer,
    int target,
    int anger,
  ) {
    if (anger == 0) return true;
    final roll =
        _hash(
          state.board.seed ^
              (state.round * 0x85ebca6b) ^
              (proposer * 131) ^
              (target * 8191),
        ) %
        4;
    return roll >= (anger == 1 ? 2 : 3);
  }
}
