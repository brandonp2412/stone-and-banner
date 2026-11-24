import '../engine/match.dart';

/// An offer must be tied to the exact recorded response, never guessed from
/// a disappearing offer (which may expire or be withdrawn).
ProposeTrade? proposalForResponse(MatchState state, RespondTrade response) {
  final index = state.events.lastIndexOf(response);
  if (index < 0) return null;
  for (var j = index - 1; j >= 0; j--) {
    final proposal = state.events[j];
    if (proposal is ProposeTrade &&
        (proposal.target == -1 || proposal.target == response.player) &&
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
      : '$recipient declined the trade: $terms.';
}

/// The events log is authoritative; proposal ownership is recoverable from
/// an immediately preceding turn boundary, without reading hidden hands.
int tradeProposerForEvent(MatchState state, int index) {
  if (index < 0 || index >= state.events.length) return -1;
  final event = state.events[index];
  if (event is ProposeTrade && event.counterOf != null) {
    if (event.counterActor != null) return event.counterActor!;
    final originalIndex = event.counterOf!;
    if (originalIndex >= 0 && originalIndex < index) {
      final original = state.events[originalIndex];
      if (original is ProposeTrade && original.target >= 0) {
        return original.target;
      }
    }
  }
  // Events are replayed deterministically, but the active seat at a past
  // proposal can also be recovered by counting subsequent EndTurn events.
  var seat = state.active;
  for (var i = state.events.length - 1; i > index; i--) {
    if (state.events[i] is EndTurn) {
      final order = state.turnOrder;
      seat = order[(order.indexOf(seat) - 1 + order.length) % order.length];
    }
  }
  return seat;
}

String? latestTradeFeedback(MatchState state, {int? viewer}) {
  for (final event in state.events.reversed) {
    if (event is! RespondTrade) continue;
    final message = tradeFeedbackForResponse(state, event, viewer: viewer);
    if (message == null) continue;
    final proposal = proposalForResponse(state, event);
    if (proposal == null || proposal.target != -1) return message;

    // A broadcast is a single decision for the player, even though each bot
    // records its own replayable response. Show all the answers together.
    final responses = state.events
        .whereType<RespondTrade>()
        .where((reply) => reply.offerId == state.events.indexOf(proposal))
        .toList();
    if (responses.length < 2) return message;
    final declines = responses
        .where((reply) => !reply.accept)
        .map((reply) => state.players[reply.player].id)
        .toList();
    final winner = responses.where((reply) => reply.accept).firstOrNull;
    final terms =
        '${tradeBundleText(proposal.gives)} for '
        '${tradeBundleText(proposal.wants)}';
    if (winner != null) {
      final accepted = state.players[winner.player].id;
      return '$accepted accepted the trade: $terms.'
          '${declines.isEmpty ? '' : ' ${declines.join(', ')} declined.'}';
    }
    return '${declines.join(', ')} declined the trade: $terms.';
  }
  return null;
}
