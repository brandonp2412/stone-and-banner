import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/ai_turn_coordinator.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';

void main() {
  MatchState advanceHuman(MatchState s) {
    while (s.actingSeat == 0 && s.phase != MatchPhase.finished) {
      final view = AiActionAdapter.observe(s, 0);
      final chosen = AiActionAdapter.decide(view);
      if (chosen == null) throw StateError('Human fixture has no action');
      s = AiActionAdapter.applySelected(s, view, chosen);
    }
    return s;
  }

  testWidgets('Space fast-forward bypasses subsequent presentation waits', (
    tester,
  ) async {
    var state = MatchEngine.newGame(['A', 'B', 'C'], 607);
    var commits = 0;
    late AiTurnCoordinator coordinator;
    coordinator = AiTurnCoordinator(
      read: () => state,
      isComputerSeat: (_) => true,
      delay: const Duration(seconds: 5),
      commit: (before, next) {
        state = next;
        if (++commits == 2) coordinator.pause();
        return true;
      },
    );
    coordinator.resume();
    coordinator.fastForward();
    await tester.pump();
    expect(commits, 1);
    await tester.pump(Duration.zero);
    expect(commits, 2);
    await tester.pump(const Duration(seconds: 5));
    await coordinator.settled;
  });

  testWidgets('decision time overlaps a regular presentation cadence', (
    tester,
  ) async {
    var state = MatchEngine.newGame(['A', 'B', 'C'], 607);
    var commits = 0;
    final ai = AiTurnCoordinator(
      read: () => state,
      commit: (expected, next) {
        state = next;
        commits++;
        return true;
      },
      isComputerSeat: (_) => true,
      delay: const Duration(milliseconds: 1800),
      decide: (state) async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return AiActionAdapter.decide(
          AiActionAdapter.observe(state, state.active),
        );
      },
    );
    ai.resume();
    await tester.pump(const Duration(milliseconds: 500));
    expect(commits, 0);
    await tester.pump(const Duration(milliseconds: 1299));
    expect(commits, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(commits, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1300));
    expect(commits, 2);
    ai.pause();
    await tester.pump(const Duration(milliseconds: 1800));
    await ai.settled;
    expect(commits, 2);
  });

  test(
    'sequential multi-seat turns return to human with exact replay',
    () async {
      var s = advanceHuman(
        MatchEngine.newGame(['Human', 'Bot A', 'Bot B'], 602),
      );
      final before = s.events.length;
      final seen = <int>[];
      final ai = AiTurnCoordinator(
        read: () => s,
        commit: (expected, next) {
          expect(identical(expected, s), isTrue);
          expect(next.events.length, s.events.length + 1);
          seen.add(next.events.length);
          s = next;
          return true;
        },
        isComputerSeat: (seat) => seat != 0,
        delay: Duration.zero,
      );
      ai.resume();
      await ai.settled;
      expect((s.tactical?.responder ?? s.active), 0);
      expect(s.events.length, greaterThan(before));
      expect(seen.toSet().length, seen.length);
      expect(
        seen,
        orderedEquals([for (var i = before + 1; i <= s.events.length; i++) i]),
      );
      expect(
        MatchEngine.exportReplay(
          MatchEngine.importReplay(MatchEngine.exportReplay(s)),
        ),
        MatchEngine.exportReplay(s),
      );
    },
  );

  test('pending computer move cancels on exit and resumes once', () async {
    var s = advanceHuman(MatchEngine.newGame(['Human', 'Bot A', 'Bot B'], 603));
    final baseline = s.events.length;
    final ai = AiTurnCoordinator(
      read: () => s,
      commit: (expected, next) {
        if (!identical(expected, s)) return false;
        s = next;
        return true;
      },
      isComputerSeat: (seat) => seat != 0,
      delay: const Duration(milliseconds: 20),
    );
    ai.resume();
    ai.pause();
    await ai.settled;
    expect(s.events.length, baseline);
    ai.resume();
    await ai.settled;
    expect(s.events.length, greaterThan(baseline));
    expect((s.tactical?.responder ?? s.active), 0);
    expect(
      MatchEngine.importReplay(MatchEngine.exportReplay(s)).events.length,
      s.events.length,
    );
  });

  test('policy illegal selection falls back to a whitelisted action', () async {
    var s = advanceHuman(MatchEngine.newGame(['Human', 'Bot A', 'Bot B'], 604));
    final baseline = s.events.length;
    final failures = <Object>[];
    final ai = AiTurnCoordinator(
      read: () => s,
      commit: (expected, next) {
        s = next;
        return true;
      },
      isComputerSeat: (seat) => seat != 0,
      decide: (_) => const PlaceRoad(-999),
      delay: Duration.zero,
      onError: failures.add,
    );
    ai.resume();
    await ai.settled;
    expect(failures, isEmpty);
    expect(s.events.length, greaterThan(baseline));
    expect((s.tactical?.responder ?? s.active), 0);
  });

  test('malformed decision stops without repeated events', () async {
    var s = advanceHuman(MatchEngine.newGame(['Human', 'Bot A', 'Bot B'], 605));
    final baseline = s.events.length;
    final failures = <Object>[];
    final ai = AiTurnCoordinator(
      read: () => s,
      commit: (expected, next) {
        s = next;
        return true;
      },
      isComputerSeat: (seat) => seat != 0,
      decide: (_) => throw const FormatException('invalid strategy state'),
      delay: Duration.zero,
      onError: failures.add,
    );
    ai.resume();
    await ai.settled;
    expect(ai.isPaused, isTrue);
    expect(failures.single, isA<FormatException>());
    expect(s.events.length, baseline);
  });

  test(
    'rapid human/computer alternation keeps a reproducible event log',
    () async {
      var s = MatchEngine.newGame(['Human', 'Bot A', 'Bot B', 'Bot C'], 606);
      final ai = AiTurnCoordinator(
        read: () => s,
        commit: (expected, next) {
          if (!identical(expected, s)) return false;
          s = next;
          return true;
        },
        isComputerSeat: (seat) => seat != 0,
        delay: Duration.zero,
        onError: (error) => fail(error.toString()),
      );
      for (
        var cycle = 0;
        cycle < 14 && s.phase != MatchPhase.finished;
        cycle++
      ) {
        s = advanceHuman(s);
        if (s.phase == MatchPhase.finished) break;
        ai.resume();
        await ai.settled;
        expect(ai.isRunning, isFalse);
        expect(AiTurnCoordinator.actingSeat(s, (seat) => seat != 0), 0);
        if (s.active != 0 && s.tactical == null) {
          final offer = s.offers
              .where((o) => o.proposer == s.active && o.canRespond(0))
              .firstOrNull;
          if (offer != null) {
            s = MatchEngine.apply(s, RespondTrade(0, false, offerId: offer.id));
          } else if (s.pendingDiscards.containsKey(0)) {
            // A seven can interrupt a bot round with a human discard.
            s = MatchEngine.apply(s, MatchEngine.idleEvent(s)!);
          }
        }
        final replay = MatchEngine.importReplay(MatchEngine.exportReplay(s));
        expect(replay.events.length, s.events.length);
        expect(replay.phase, s.phase);
      }
      expect(s.events.length, greaterThan(50));
    },
  );

  test('trade offered by bot to human never blocks bot turn', () async {
    var state = MatchEngine.newGame(['Host', 'Bot', 'Other'], 614).copyWith(
      phase: MatchPhase.actions,
      active: 1,
      offers: [TradeProposal(42, 1, 0, Resource.wood, 1, Resource.wool, 1)],
    );
    expect(AiTurnCoordinator.actingSeat(state, (seat) => seat == 1), 1);
    final failures = <Object>[];
    final ai = AiTurnCoordinator(
      read: () => state,
      isComputerSeat: (seat) => seat == 1,
      delay: Duration.zero,
      decide: (_) => const EndTurn(),
      onError: failures.add,
      commit: (before, next) {
        expect(identical(state, before), isTrue);
        state = next;
        return true;
      },
    );
    ai.resume();
    await ai.settled.timeout(const Duration(seconds: 5));
    expect(failures, isEmpty);
    expect(state.active, 2);
    expect(state.events.last, isA<EndTurn>());
  });

  test('AI move quota resets each turn even without a human turn', () async {
    var state = MatchEngine.newGame([
      'Host',
      'Bot A',
      'Bot B',
    ], 615).copyWith(phase: MatchPhase.actions, active: 1);
    final failures = <Object>[];
    var commits = 0;
    final ai = AiTurnCoordinator(
      read: () => state,
      isComputerSeat: (seat) => seat != 0,
      delay: Duration.zero,
      maxEventsPerRun: 1,
      decide: (_) => const EndTurn(),
      onError: failures.add,
      commit: (before, next) {
        commits++;
        state = next.copyWith(phase: MatchPhase.actions);
        return true;
      },
    );
    ai.resume();
    await ai.settled.timeout(const Duration(seconds: 5));
    expect(failures, isEmpty);
    expect(commits, 2);
    expect(state.active, 0);
  });

  test(
    'stale owner rejects commit without spending any goods or events',
    () async {
      var s = advanceHuman(
        MatchEngine.newGame(['Human', 'Bot A', 'Bot B'], 607),
      );
      final before = MatchEngine.exportReplay(s);
      var rejected = 0;
      final ai = AiTurnCoordinator(
        read: () => s,
        commit: (expected, next) {
          rejected++;
          return false;
        },
        isComputerSeat: (seat) => seat != 0,
        delay: Duration.zero,
      );
      ai.resume();
      await ai.settled;
      expect(rejected, 1);
      expect(MatchEngine.exportReplay(s), before);
    },
  );
}
