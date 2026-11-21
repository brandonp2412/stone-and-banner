import 'dart:async';

import 'ai.dart';
import 'ai_cards.dart';
import 'heuristic_ai.dart';
import 'match.dart';

/// Runs only the seats explicitly owned by the local offline computer.
/// The callback must atomically reject a state that has changed since [read].
typedef AiStateCommit = bool Function(MatchState expected, MatchState next);
typedef AiDecision = FutureOr<MatchEvent?> Function(MatchState state);

class AiTurnCoordinator {
  AiTurnCoordinator({
    required this.read,
    required this.commit,
    required this.isComputerSeat,
    this.onProgress,
    this.onError,
    this.delay = const Duration(milliseconds: 45),
    this.maxEventsPerRun = 96,
    AiDecision? decide,
  }) : _decide = decide ?? const HeuristicAi().choose {
    if (maxEventsPerRun < 1) {
      throw ArgumentError.value(maxEventsPerRun, 'maxEventsPerRun');
    }
  }

  final MatchState? Function() read;
  final AiStateCommit commit;
  final bool Function(int seat) isComputerSeat;
  final void Function(int count)? onProgress;
  final void Function(Object error)? onError;
  Duration delay;
  Completer<void>? _delayGate;
  bool _fastForward = false;

  void fastForward() {
    _fastForward = true;
    skipDelay();
  }

  void skipDelay() =>
      _delayGate?.isCompleted == false ? _delayGate!.complete() : null;

  Future<void> _presentationDelay() async {
    if (_fastForward) return;
    final gate = Completer<void>();
    _delayGate = gate;
    await Future.any([Future<void>.delayed(delay), gate.future]);
    if (identical(_delayGate, gate)) _delayGate = null;
  }

  final int maxEventsPerRun;
  final AiDecision _decide;

  bool _paused = true;
  bool _running = false;
  int _generation = 0;
  Future<void> _work = Future<void>.value();

  /// Only *computer* responders pre-empt the active seat. Human recipients
  /// must never freeze a bot's turn until the 90-second idle deadline; host
  /// controllers may provide a short bounded human-response window instead.
  static int actingSeat(MatchState state, bool Function(int) isComputerSeat) {
    if (state.tactical == null && state.phase == MatchPhase.actions) {
      for (final offer in state.offers) {
        if (offer.proposer != state.active) continue;
        if (offer.target == -1) {
          // Give humans first refusal on a computer's broadcast. The room
          // scheduler owns the bounded response period, then the bot resumes.
          // Otherwise a second bot could instantly accept before the human
          // even receives the trade proposal.
          if (isComputerSeat(offer.proposer) &&
              List.generate(state.players.length, (seat) => seat).any(
                (seat) => !isComputerSeat(seat) && offer.canRespond(seat),
              )) {
            return state.active;
          }
          for (var seat = 0; seat < state.players.length; seat++) {
            if (isComputerSeat(seat) && offer.canRespond(seat)) return seat;
          }
        } else if (isComputerSeat(offer.target) &&
            offer.canRespond(offer.target)) {
          return offer.target;
        }
      }
    }
    return state.actingSeat;
  }

  bool get isPaused => _paused;
  bool get isRunning => _running;
  Future<void> get settled => _work;

  /// Idempotent. A cancelled pump cannot dispatch a stale event after resume.
  void resume() {
    _paused = false;
    if (_running) return;
    _running = true;
    final ticket = ++_generation;
    _work = _drive(ticket);
  }

  /// Synchronous invalidation before the next event. Safe during app exit,
  /// hot-seat privacy handoff, lifecycle suspension and match replacement.
  void pause() {
    _paused = true;
    _fastForward = false;
    _generation++;
  }

  static RespondTrade _answerOffer(
    MatchState state,
    int seat,
    TradeProposal offer,
  ) {
    final view = AiActionAdapter.observe(
      state.copyWith(active: seat, offers: [offer]),
      seat,
    );
    final answer = AiCardStrategy.incomingOffer(view);
    return answer is RespondTrade
        ? answer
        : RespondTrade(seat, false, offerId: offer.id);
  }

  Future<void> _drive(int ticket) async {
    var events = 0;
    int? countedTurn;
    try {
      while (!_paused && ticket == _generation) {
        final before = read();
        if (before == null || before.phase == MatchPhase.finished) return;
        if (countedTurn != before.turnSerial) {
          countedTurn = before.turnSerial;
          events = 0;
        }
        final seat = actingSeat(before, isComputerSeat);
        final immediateReply = seat != (before.actingSeat);
        if (!isComputerSeat(seat)) {
          _fastForward = false;
          return;
        }
        if (events >= maxEventsPerRun) {
          throw StateError(
            'Computer exceeded the safe action limit for this turn.',
          );
        }

        // Everyone evaluates the same broadcast independently. Present the
        // replies together instead of making each bot wait for another turn's
        // animation. Apply declines first, then at most one acceptance: a
        // successful trade closes the offer for all other recipients.
        TradeProposal? broadcast;
        if (immediateReply) {
          for (final offer in before.offers) {
            if (offer.proposer == before.active &&
                offer.target == -1 &&
                offer.canRespond(seat)) {
              broadcast = offer;
              break;
            }
          }
        }
        if (broadcast != null) {
          final recipients = [
            for (
              var candidate = 0;
              candidate < before.players.length;
              candidate++
            )
              if (isComputerSeat(candidate) && broadcast.canRespond(candidate))
                candidate,
          ];
          if (recipients.length > 1) {
            final replies = [
              for (final recipient in recipients)
                _answerOffer(before, recipient, broadcast),
            ];
            final declines = replies.where((reply) => !reply.accept).toList();
            final acceptances = replies.where((reply) => reply.accept);
            final winner = acceptances.isEmpty ? null : acceptances.first;
            final ordered = [...declines, ?winner];
            if (events + ordered.length > maxEventsPerRun) {
              throw StateError(
                'Computer exceeded the safe action limit for this turn.',
              );
            }
            await _presentationDelay();
            if (_paused || ticket != _generation) return;
            if (!identical(before, read())) continue;
            var expected = before;
            for (final reply in ordered) {
              if (_paused ||
                  ticket != _generation ||
                  !identical(expected, read())) {
                return;
              }
              final next = MatchEngine.apply(expected, reply);
              if (!commit(expected, next)) return;
              onProgress?.call(++events);
              // Network hosts re-run the reducer when recording a move, so
              // their stored state is equivalent to `next` but not identical.
              // Use the authoritative read-back for the next response.
              final committed = read();
              if (committed == null ||
                  committed.events.length != next.events.length ||
                  committed.events.last is! RespondTrade) {
                return;
              }
              expected = committed;
            }
            continue;
          }
        }

        // Yield even in tests with a zero delay. No wall clock enters the
        // reducer, seed, policy or replay; this only schedules presentation.
        // Think during the presentation interval, so decision time is not
        // added as a second pause between actions. Await both to handle errors
        // even if the pump is cancelled while the decision is in flight.
        final results = await Future.wait<Object?>([
          Future<MatchEvent?>.sync(() {
            if (!immediateReply) return _decide(before);
            final offer = before.offers.firstWhere(
              (o) => o.proposer == before.active && o.canRespond(seat),
            );
            return _answerOffer(before, seat, offer);
          }).onError<StateError>((error, stack) => null),
          // Every visible computer action receives the same presentation
          // interval, regardless of whether the previous event was a trade,
          // dice roll, construction or turn transition.
          _presentationDelay(),
        ]);
        if (_paused || ticket != _generation) return;

        final current = read();
        if (current == null || !identical(before, current)) continue;
        final view = AiActionAdapter.observe(
          immediateReply ? current.copyWith(active: seat) : current,
          seat,
        );
        if (view.legalActions.isEmpty) {
          throw StateError('Computer has no legal action for this phase.');
        }

        // A policy bug may propose an unavailable event. Revalidate through
        // the adapter, then fall back to its bounded deterministic choice.
        MatchState next;
        try {
          final preferred = results.first as MatchEvent?;
          if (preferred == null) throw StateError('No computer decision.');
          next = immediateReply
              ? MatchEngine.apply(current, preferred)
              : AiActionAdapter.applySelected(current, view, preferred);
        } on StateError {
          final safe = immediateReply
              ? RespondTrade(
                  seat,
                  false,
                  offerId: current.offers
                      .firstWhere(
                        (o) =>
                            o.canRespond(seat) && o.proposer == current.active,
                      )
                      .id,
                )
              : AiActionAdapter.decide(view);
          if (safe == null) {
            throw StateError('Computer cannot recover a legal action.');
          }
          next = immediateReply
              ? MatchEngine.apply(current, safe)
              : AiActionAdapter.applySelected(current, view, safe);
        }
        if (next.events.length != current.events.length + 1) {
          throw StateError('Computer action did not append exactly one event.');
        }
        if (_paused || ticket != _generation || !commit(current, next)) {
          return;
        }
        onProgress?.call(++events);
      }
    } on Object catch (error) {
      // Do not retry an unknown malformed state in a tight event loop.
      pause();
      onError?.call(error);
    } finally {
      _running = false;
      // pause() followed by resume() during an outstanding yield starts
      // exactly one fresh pump after the cancelled one exits.
      if (!_paused && ticket != _generation) resume();
    }
  }
}
