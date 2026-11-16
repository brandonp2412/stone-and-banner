import '../engine/match.dart';

/// Public trade outcomes come from recorded responses, never inferred from
/// disappearing offers (which may also have expired or been withdrawn).
String? latestTradeFeedback(MatchState state) {
  for (var i = state.events.length - 1; i >= 0; i--) {
    final response = state.events[i];
    if (response is! RespondTrade) continue;
    for (var j = i - 1; j >= 0; j--) {
      final proposal = state.events[j];
      if (proposal is! ProposeTrade ||
          proposal.target != response.player ||
          (response.offerId != null && response.offerId != j)) {
        continue;
      }
      final recipient = state.players[response.player].id;
      final terms =
          '${proposal.giveCount} ${proposal.give.name} for '
          '${proposal.wantCount} ${proposal.want.name}';
      return response.accept
          ? '$recipient accepted the trade: $terms.'
          : '$recipient declined the trade: $terms. Reserved goods returned.';
    }
  }
  return null;
}
