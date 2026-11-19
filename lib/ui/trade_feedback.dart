import '../engine/match.dart';

/// An offer must be tied to the exact recorded response, never guessed from
/// a disappearing offer (which may expire or be withdrawn).
ProposeTrade? proposalForResponse(MatchState state, RespondTrade response) {
  final index = state.events.lastIndexOf(response);
  if (index < 0) return null;
  for (var j = index - 1; j >= 0; j--) {
    final proposal = state.events[j];
    if (proposal is ProposeTrade &&
        proposal.target == response.player &&
        (response.offerId == null || response.offerId == j)) {
      return proposal;
    }
  }
  return null;
}

/// [viewer] suppresses trades between other players, especially AI vs AI.
/// Omit it for match-replay summaries that deliberately show public activity.
String? tradeFeedbackForResponse(
  MatchState state,
  RespondTrade response, {
  int? viewer,
}) {
  final proposal = proposalForResponse(state, response);
  if (proposal == null) return null;
  // When no explicit proposer is encoded in the event, replay state at the
  // proposal's offset to identify the actual owner, not the current turn.
  final proposalIndex = state.events.indexOf(proposal);
  final proposer = tradeProposerForEvent(state, proposalIndex);
  if (viewer != null && viewer != proposer && viewer != response.player) {
    return null;
  }
  final recipient = state.players[response.player].id;
  final terms =
      '${tradeBundleText(proposal.gives)} for '
      '${tradeBundleText(proposal.wants)}';
  return response.accept
      ? '$recipient accepted the trade: $terms.'
      : '$recipient declined the trade: $terms. Reserved goods returned.';
}

/// The events log is authoritative; proposal ownership is recoverable from
/// an immediately preceding turn boundary, without reading hidden hands.
int tradeProposerForEvent(MatchState state, int index) {
  if (index < 0) return -1;
  // Events are replayed deterministically, but the active seat at a past
  // proposal can also be recovered by counting subsequent EndTurn events.
  var seat = state.active;
  for (var i = state.events.length - 1; i > index; i--) {
    if (state.events[i] is EndTurn) {
      seat = (seat - 1 + state.players.length) % state.players.length;
    }
  }
  return seat;
}

String? latestTradeFeedback(MatchState state, {int? viewer}) {
  for (final event in state.events.reversed) {
    if (event is! RespondTrade) continue;
    final message = tradeFeedbackForResponse(state, event, viewer: viewer);
    if (message != null) return message;
  }
  return null;
}
