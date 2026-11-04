import 'dart:async';

import 'ai.dart';
import 'heuristic_ai.dart';
import 'match.dart';

/// Runs only the seats explicitly owned by the local offline computer.
/// The callback must atomically reject a state that has changed since [read].
typedef AiStateCommit = bool Function(MatchState expected, MatchState next);
typedef AiDecision = MatchEvent? Function(MatchState state);

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
  final Duration delay;
  final int maxEventsPerRun;
  final AiDecision _decide;

  bool _paused = true;
  bool _running = false;
  int _generation = 0;
  Future<void> _work = Future<void>.value();

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
    _generation++;
  }

  Future<void> _drive(int ticket) async {
    var events = 0;
    try {
      while (!_paused && ticket == _generation) {
        final before = read();
        if (before == null || before.phase == MatchPhase.finished) return;
        final seat = before.tactical?.responder ?? before.active;
        if (!isComputerSeat(seat)) return;
        if (events >= maxEventsPerRun) {
          throw StateError('Computer move limit reached. Resume to continue.');
        }

        // Yield even in tests with a zero delay. No wall clock enters the
        // reducer, seed, policy or replay; this only schedules presentation.
        await Future<void>.delayed(delay);
        if (_paused || ticket != _generation) return;

        final current = read();
        if (current == null || !identical(before, current)) continue;
        final view = AiActionAdapter.observe(current, seat);
        if (view.legalActions.isEmpty) {
          throw StateError('Computer has no legal action for this phase.');
        }

        // A policy bug may propose an unavailable event. Revalidate through
        // the adapter, then fall back to its bounded deterministic choice.
        MatchState next;
        try {
          final preferred = _decide(current);
          if (preferred == null) throw StateError('No computer decision.');
          next = AiActionAdapter.applySelected(current, view, preferred);
        } on StateError {
          final safe = AiActionAdapter.decide(view);
          if (safe == null) {
            throw StateError('Computer cannot recover a legal action.');
          }
          next = AiActionAdapter.applySelected(current, view, safe);
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
