import 'dart:io';

import 'package:stone_and_banner/engine/heuristic_ai.dart';
import 'package:stone_and_banner/engine/match.dart';

/// Produce an independent, repeatable match for public screenshots.
/// Every placement and turn passes through the normal engine reducer.
void main() {
  var state = MatchEngine.newGame(
    ['Rowan', 'Elara', 'Mira'],
    987654,
    cardDeckVersion: 2,
  );
  const policy = HeuristicAi();
  for (var step = 0; step < 1500; step++) {
    if (state.round >= 6 &&
        state.active == 0 &&
        state.phase == MatchPhase.actions &&
        state.tactical == null) {
      // Resolve outstanding offers so imports open on the board rather than
      // an incoming-trade dialog. These are ordinary, recorded responses.
      for (final offer in state.offers.toList()) {
        if (offer.proposer == state.active) {
          state = MatchEngine.apply(state, WithdrawTrade(offer.id));
        } else if (offer.canRespond(state.active)) {
          state = MatchEngine.apply(
            state,
            RespondTrade(state.active, false, offerId: offer.id),
          );
        }
      }
      final replay = MatchEngine.exportReplay(state);
      if (MatchEngine.snapshot(MatchEngine.importReplay(replay)) !=
          MatchEngine.snapshot(state)) {
        throw StateError('Screenshot replay did not reconstruct its state.');
      }
      stdout.write(replay);
      return;
    }
    final event = policy.choose(state);
    if (event == null) throw StateError('Screenshot match has no legal move.');
    state = MatchEngine.apply(state, event);
  }
  throw StateError('Screenshot match did not reach the requested turn.');
}
