import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/p2p_room.dart';

void main() {
  test('AI bots continue across eight rounds without manual resume', () async {
    final room = P2pRoom(
      botMoveDelay: Duration.zero,
      humanTradeGrace: const Duration(milliseconds: 5),
    );
    addTearDown(room.dispose);
    room.host('Host', 3, 71253);
    room.setBotCount(2);
    room.start();

    final started = DateTime.now();
    var humanMoves = 0;
    var iterations = 0;
    var staleCycles = 0;
    var lastVersion = -1;
    while (room.game != null &&
        room.game!.phase != MatchPhase.finished &&
        room.game!.round < 8 &&
        iterations++ < 1800) {
      if (DateTime.now().difference(started) > const Duration(seconds: 65)) {
        fail('The AI took more than 65 seconds to reach round 8');
      }
      final s = room.authoritativeStateForTest!;
      // The host must answer out-of-turn Bandit discards and raid reactions
      // even when a bot owns the active turn; otherwise gameplay waits for
      // an unmodelled human response and appears stuck.
      if (s.actingSeat == 0) {
        final view = AiActionAdapter.observe(s, 0);
        final event = AiActionAdapter.decide(view);
        expect(event, isNotNull);
        room.dispatch(event!);
        humanMoves++;
      } else if (s.tactical?.responder == 0) {
        final view = AiActionAdapter.observe(s, 0);
        final event = AiActionAdapter.decide(view);
        expect(event, isNotNull);
        room.dispatch(event!);
        humanMoves++;
      }
      await room.aiSettled.timeout(const Duration(seconds: 15));
      await Future<void>.delayed(const Duration(milliseconds: 7));
      if (room.version == lastVersion) {
        staleCycles++;
        expect(
          staleCycles,
          lessThan(130),
          reason:
              'AI stuck at round ${s.round}, active ${s.active}, acting ${s.actingSeat}, phase ${s.phase}, offers ${s.offers.map((o) => o.proposer).toList()}, state version ${room.version}, bot actions ${room.aiMoveCount}, bot error ${room.aiError}, dispatch error ${room.message}',
        );
      } else {
        staleCycles = 0;
      }
      lastVersion = room.version;
      expect(
        room.aiError,
        isNull,
        reason: 'Bots must recover without a Resume computer button',
      );
    }
    expect(room.game, isNotNull);
    expect(room.game!.round, greaterThanOrEqualTo(8));
    expect(room.aiMoveCount, greaterThan(35));
    expect(humanMoves, greaterThan(8));
    expect(iterations, lessThan(1800));
  }, timeout: const Timeout(Duration(seconds: 95)));
  test('bot trade expires promptly and resumes without a 90s timeout', () async {
    final room = P2pRoom(
      botMoveDelay: Duration.zero,
      humanTradeGrace: const Duration(milliseconds: 40),
    );
    addTearDown(room.dispose);
    room.host('Host', 3, 71123);
    room.setBotCount(2);
    room.start();
    room.replaceHostStateForTest((current) {
      final players = current.players.toList();
      players[0] = players[0].copyWith(
        stores: {...players[0].stores, Resource.wool: 3},
      );
      players[1] = players[1].copyWith(
        stores: {...players[1].stores, Resource.wood: 3},
      );
      final prepared = current.copyWith(
        phase: MatchPhase.actions,
        active: 1,
        players: players,
      );
      return MatchEngine.apply(
        prepared,
        const ProposeTrade(0, Resource.wood, 1, Resource.wool, 1),
      );
    });
    expect(room.game!.offers, isNotEmpty);
    expect(room.aiMoveCount, 0);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(room.aiMoveCount, 0, reason: 'Human gets a response grace period');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await room.aiSettled.timeout(const Duration(seconds: 8));
    expect(room.aiError, isNull);
    expect(
      room.aiMoveCount,
      greaterThan(0),
      reason:
          'Bot must move when trade grace expires, not after 90-second timeout',
    );
  });

  test(
    'broadcast batch authorizes each bot responder, not the first seat',
    () async {
      final room = P2pRoom(botMoveDelay: Duration.zero);
      addTearDown(room.dispose);
      room.host('Host', 3, 71244);
      room.setBotCount(2);
      room.start();
      room.replaceHostStateForTest((current) {
        final players = current.players.toList();
        players[0] = players[0].copyWith(stores: {Resource.wood: 3});
        players[1] = players[1].copyWith(stores: {Resource.wheat: 1});
        players[2] = players[2].copyWith(stores: const {});
        return MatchEngine.apply(
          current.copyWith(
            phase: MatchPhase.actions,
            active: 0,
            players: players,
          ),
          const ProposeTrade(-1, Resource.wood, 3, Resource.wheat, 1),
        );
      });
      await room.aiSettled.timeout(const Duration(seconds: 8));
      expect(room.aiError, isNull);
      final replies = room.authoritativeStateForTest!.events
          .whereType<RespondTrade>()
          .toList();
      expect(replies.map((r) => (r.player, r.accept)).toList(), [
        (2, false),
        (1, true),
      ], reason: 'Declining bot replies first even when a lower seat accepts');
      expect(room.authoritativeStateForTest!.offers, isEmpty);
      expect(
        room.authoritativeStateForTest!.players[0].stores[Resource.wheat],
        1,
      );
      expect(
        room.authoritativeStateForTest!.players[1].stores[Resource.wood],
        3,
      );
    },
  );

  test('human trade decline releases waiting bot immediately', () async {
    final room = P2pRoom(
      botMoveDelay: Duration.zero,
      humanTradeGrace: const Duration(seconds: 30),
    );
    addTearDown(room.dispose);
    room.host('Host', 3, 71241);
    room.setBotCount(2);
    room.start();
    room.replaceHostStateForTest((current) {
      final players = current.players.toList();
      players[0] = players[0].copyWith(
        stores: {...players[0].stores, Resource.wool: 3},
      );
      players[1] = players[1].copyWith(
        stores: {...players[1].stores, Resource.wood: 3},
      );
      return MatchEngine.apply(
        current.copyWith(
          phase: MatchPhase.actions,
          active: 1,
          players: players,
        ),
        const ProposeTrade(0, Resource.wood, 1, Resource.wool, 1),
      );
    });
    final id = room.game!.offers.single.id;
    expect(room.aiMoveCount, 0);
    room.dispatch(RespondTrade(0, false, offerId: id));
    await room.aiSettled.timeout(const Duration(seconds: 8));
    expect(room.aiError, isNull);
    expect(
      room.aiMoveCount,
      greaterThan(0),
      reason: 'Human reply should release AI without manual resume',
    );
  });
  test(
    'three AI crashes automatically recover using validated idle moves',
    () async {
      var decisions = 0;
      final room = P2pRoom(
        botMoveDelay: Duration.zero,
        humanTradeGrace: const Duration(milliseconds: 5),
        botDecisionForTest: (state) {
          decisions++;
          throw const FormatException('Injected AI inference crash');
        },
      );
      addTearDown(room.dispose);
      room.host('Host', 3, 71880);
      room.setBotCount(2);
      room.start();
      room.replaceHostStateForTest(
        (state) => state.copyWith(phase: MatchPhase.actions, active: 1),
      );
      final limit = DateTime.now().add(const Duration(seconds: 9));
      while (room.authoritativeStateForTest!.active != 0 &&
          DateTime.now().isBefore(limit)) {
        await Future<void>.delayed(const Duration(milliseconds: 35));
      }
      expect(
        room.authoritativeStateForTest!.active,
        0,
        reason: 'Bot fallback should pass both seats without manual resume',
      );
      expect(room.aiError, isNull);
      expect(decisions, greaterThanOrEqualTo(6));
      expect(
        room.game!.events.whereType<EndTurn>().length,
        greaterThanOrEqualTo(2),
      );
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
