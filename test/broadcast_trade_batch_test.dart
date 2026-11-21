import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai_turn_coordinator.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/trade_feedback.dart';

MatchState _fundedGame({bool secondBotCanPay = true}) {
  final fresh = MatchEngine.newGame([
    'Human',
    'Bob',
    'Alice',
  ], 95).copyWith(phase: MatchPhase.actions);
  final players = fresh.players.toList();
  players[0] = players[0].copyWith(stores: {Resource.wood: 3});
  players[1] = players[1].copyWith(stores: {Resource.wheat: 2});
  players[2] = players[2].copyWith(
    stores: secondBotCanPay ? {Resource.wheat: 2} : <Resource, int>{},
  );
  return fresh.copyWith(players: players);
}

Future<MatchState> _resolve(
  MatchState state, {
  Duration delay = Duration.zero,
  bool networkStyleCommit = false,
}) async {
  final errors = <Object>[];
  final coordinator = AiTurnCoordinator(
    read: () => state,
    isComputerSeat: (seat) => seat != 0,
    delay: delay,
    commit: (expected, next) {
      expect(identical(expected, state), isTrue);
      // Hosted rooms replay the event and keep a new (non-identical) state.
      state = networkStyleCommit
          ? MatchEngine.apply(expected, next.events.last)
          : next;
      return true;
    },
    onError: errors.add,
  );
  coordinator.resume();
  await coordinator.settled;
  expect(errors, isEmpty);
  return state;
}

void main() {
  test('all bots decline the same offer in one batch', () async {
    final initial = MatchEngine.apply(
      _fundedGame(),
      const ProposeTrade(-1, Resource.wood, 1, Resource.wheat, 2),
    );
    final state = await _resolve(initial, networkStyleCommit: true);
    expect(state.events.length, initial.events.length + 2);
    expect(state.offers, isEmpty);
    final answers = state.events.whereType<RespondTrade>().toList();
    expect(answers.map((r) => (r.player, r.accept)), [(1, false), (2, false)]);
    expect(
      latestTradeFeedback(state, viewer: 0),
      contains('Bob, Alice declined'),
    );
  });

  test('one bot accepts while the other declines in the same batch', () async {
    final initial = MatchEngine.apply(
      _fundedGame(secondBotCanPay: false),
      const ProposeTrade(-1, Resource.wood, 3, Resource.wheat, 1),
    );
    final state = await _resolve(initial);
    expect(state.events.length, initial.events.length + 2);
    expect(
      state.events.whereType<RespondTrade>().map((r) => (r.player, r.accept)),
      [(2, false), (1, true)],
    );
    expect(state.offers, isEmpty);
    expect(state.players[0].stores[Resource.wood], 0);
    expect(state.players[0].stores[Resource.wheat], 1);
    expect(state.players[1].stores[Resource.wood], 3);
    expect(state.players[2].stores[Resource.wood] ?? 0, 0);
    expect(latestTradeFeedback(state, viewer: 0), contains('Bob accepted'));
    expect(latestTradeFeedback(state, viewer: 0), contains('Alice declined'));
  });

  test('two willing bots cannot execute two acceptances', () async {
    final initial = MatchEngine.apply(
      _fundedGame(),
      const ProposeTrade(-1, Resource.wood, 3, Resource.wheat, 1),
    );
    final state = await _resolve(initial);
    expect(state.events.length, initial.events.length + 1);
    expect(state.events.last, isA<RespondTrade>());
    final winner = state.events.last as RespondTrade;
    expect(winner.player, 1);
    expect(winner.accept, isTrue);
    expect(state.players[0].stores[Resource.wheat], 1);
    expect(state.players[2].stores[Resource.wheat], 2);
  });
}
