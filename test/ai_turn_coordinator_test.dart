import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/ai_turn_coordinator.dart';
import 'package:stone_and_banner/engine/match.dart';

void main() {
  MatchState advanceHuman(MatchState s) {
    while ((s.tactical?.responder ?? s.active) == 0 &&
        s.phase != MatchPhase.finished) {
      final view = AiActionAdapter.observe(s, 0);
      final chosen = AiActionAdapter.decide(view);
      if (chosen == null) throw StateError('Human fixture has no action');
      s = AiActionAdapter.applySelected(s, view, chosen);
    }
    return s;
  }

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
        expect((s.tactical?.responder ?? s.active), 0);
        final replay = MatchEngine.importReplay(MatchEngine.exportReplay(s));
        expect(replay.events.length, s.events.length);
        expect(replay.phase, s.phase);
      }
      expect(s.events.length, greaterThan(50));
    },
  );

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
