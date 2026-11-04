import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

void main() {
  MatchState newMatch(int seed, {int seats = 3}) =>
      MatchEngine.newGame(List.generate(seats, (i) => 'Seat-$i'), seed);

  String actionKeys(AiTurnView view) =>
      jsonEncode(view.legalActions.map((event) => event.toJson()).toList());

  test('only the active/responder seat sees its own immutable hand', () {
    final initial = newMatch(31);
    expect(() => AiActionAdapter.observe(initial, 1), throwsStateError);
    expect(() => AiActionAdapter.observe(initial, -1), throwsRangeError);
    final first = AiActionAdapter.observe(initial, 0);
    expect(first.ownCards, isEmpty);
    expect(first.ownGoods, isEmpty);
    expect(first.publicScores, hasLength(3));
    expect(() => first.ownGoods[Resource.ore] = 1, throwsUnsupportedError);
    expect(() => first.legalActions.clear(), throwsUnsupportedError);

    final changedPlayers = initial.players.toList();
    changedPlayers[1] = changedPlayers[1].copyWith(
      stores: {Resource.ore: 17, Resource.wheat: 2},
      cards: [HeldCard(StrategyDeck.governance, 0)],
    );
    changedPlayers[2] = changedPlayers[2].copyWith(
      cards: [HeldCard(StrategyDeck.innovation, 1)],
    );
    final changed = initial.copyWith(players: changedPlayers);
    final second = AiActionAdapter.observe(changed, 0);
    expect(actionKeys(second), actionKeys(first));
    expect(
      AiActionAdapter.decide(second)!.toJson(),
      AiActionAdapter.decide(first)!.toJson(),
    );

    // The adapter doesn't expose a MatchState or opponent hand reference.
    expect(first.ownGoods, isNot(same(initial.players[1].stores)));
    expect(first.ownCards, isNot(same(initial.players[1].cards)));
  });

  test('setup and dice emit only accepted engine events', () {
    var state = newMatch(13);
    for (var i = 0; i < 13; i++) {
      final view = AiActionAdapter.observe(state, state.active);
      expect(view.legalActions, isNotEmpty);
      for (final event in view.legalActions) {
        expect(
          () => MatchEngine.apply(state, event),
          returnsNormally,
          reason: '${state.phase} / ${event.toJson()}',
        );
      }
      state = AiActionAdapter.applySelected(
        state,
        view,
        AiActionAdapter.decide(view)!,
      );
    }
    final stale = AiActionAdapter.observe(state, state.active);
    expect(
      () => AiActionAdapter.applySelected(state, stale, const PlaceVillage(-1)),
      throwsStateError,
    );
    final selected = AiActionAdapter.decide(stale)!;
    final advanced = AiActionAdapter.applySelected(state, stale, selected);
    expect(
      () => AiActionAdapter.applySelected(advanced, stale, selected),
      throwsStateError,
    );
  });

  test('unplayable hidden-target card never exposes rival goods', () {
    final state = newMatch(52);
    final index = StrategyCards.deck(StrategyDeck.governance)
        .indexWhere((card) => card.power == CardPower.seizeGood);
    expect(index, greaterThanOrEqualTo(0));
    final players = state.players.toList();
    players[0] = players[0].copyWith(
      cards: [HeldCard(StrategyDeck.governance, index)],
    );
    final actionState = state.copyWith(
      players: players,
      phase: MatchPhase.actions,
    );
    final view = AiActionAdapter.observe(actionState, 0);
    expect(view.ownCards, hasLength(1));
    expect(view.legalActions.whereType<PlayStrategyCard>(), isEmpty);
    expect(view.legalActions.whereType<DiscardStrategyCard>(), hasLength(1));
    expect(view.legalActions.whereType<EndTurn>(), hasLength(1));

    final withHiddenGoods = players.toList();
    withHiddenGoods[1] = players[1].copyWith(
      stores: {Resource.wheat: 12, Resource.ore: 7},
      cards: [HeldCard(StrategyDeck.governance, index)],
    );
    final other = AiActionAdapter.observe(
      actionState.copyWith(players: withHiddenGoods),
      0,
    );
    expect(actionKeys(view), actionKeys(other));
    expect(
      AiActionAdapter.decide(view)!.toJson(),
      AiActionAdapter.decide(other)!.toJson(),
    );
  });

  test('Bandit movement is legal without spying on victims', () {
    final state = newMatch(61).copyWith(phase: MatchPhase.bandit);
    final view = AiActionAdapter.observe(state, 0);
    expect(view.legalActions, hasLength(state.board.tiles.length - 1));
    for (final move in view.legalActions.whereType<MoveBandit>()) {
      expect(move.victim, isNull);
      expect(() => MatchEngine.apply(state, move), returnsNormally);
    }
  });

  test('out-of-turn tactical seat may pass or pledge its own goods', () {
    final initial = newMatch(42);
    final players = initial.players.toList();
    players[1] = players[1].copyWith(stores: {Resource.wheat: 1});
    final state = initial.copyWith(
      players: players,
      phase: MatchPhase.invasion,
      tactical: TacticalWindow(0, TacticalKind.invasion, 0, [1]),
    );
    expect(() => AiActionAdapter.observe(state, 0), throwsStateError);
    final view = AiActionAdapter.observe(state, 1);
    expect(view.legalActions.whereType<RespondTactical>(), hasLength(2));
    for (final response in view.legalActions) {
      expect(() => MatchEngine.apply(state, response), returnsNormally);
    }
    expect(
      view.legalActions.whereType<RespondTactical>().first.choice,
      TacticalChoice.pass,
    );
  });

  test('finished phase has a score view but no legal AI event', () {
    final state = newMatch(71).copyWith(phase: MatchPhase.finished);
    final view = AiActionAdapter.observe(state, state.active);
    expect(view.publicScores, [
      for (var seat = 0; seat < state.players.length; seat++)
        MatchEngine.score(state, seat),
    ]);
    expect(view.legalActions, isEmpty);
    expect(AiActionAdapter.decide(view), isNull);
  });

  test('seeded choices cannot deadlock across 3- and 4-seat games', () {
    for (final seats in [3, 4]) {
      for (final seed in [1, 17, 204]) {
        var state = newMatch(seed, seats: seats);
        var steps = 0;
        while (state.phase != MatchPhase.finished &&
            state.round < 9 &&
            steps < 1800) {
          final actor = state.tactical?.responder ?? state.active;
          final view = AiActionAdapter.observe(state, actor);
          expect(
            view.legalActions,
            isNotEmpty,
            reason: 'seed=$seed seats=$seats phase=${state.phase}',
          );
          // Sample complete candidate sets, not merely the chosen event.
          if (steps % 19 == 0) {
            for (final event in view.legalActions) {
              expect(
                () => MatchEngine.apply(state, event),
                returnsNormally,
                reason: 'seed=$seed seats=$seats ${event.toJson()}',
              );
            }
          }
          final chosen = AiActionAdapter.decide(view)!;
          expect(
            AiActionAdapter.decide(AiActionAdapter.observe(state, actor))!
                .toJson(),
            chosen.toJson(),
          );
          final next = AiActionAdapter.applySelected(state, view, chosen);
          expect(next.events.length, state.events.length + 1);
          state = next;
          steps++;
        }
        expect(
          steps,
          lessThan(1800),
          reason: 'seed=$seed seats=$seats round=${state.round}',
        );
        expect(state.phase == MatchPhase.finished || state.round >= 9, isTrue);
        final replay = MatchEngine.replay(
          List.generate(seats, (i) => 'Seat-$i'),
          seed,
          state.events,
        );
        expect(MatchEngine.snapshot(replay), MatchEngine.snapshot(state));
      }
    }
  });
}
