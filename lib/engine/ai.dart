import 'dart:convert';

import 'board.dart';
import 'cards.dart';
import 'game.dart';
import 'match.dart';

/// A deliberately narrow observation for an offline AI seat.
///
/// No MatchState, other player's stores/cards, deck order or replay seed is
/// exposed to the decision policy. Only the trusted host calls [observe].
class AiTurnView {
  AiTurnView._(
    this._seed, {
    required this.seat,
    required this.phase,
    required this.activeSeat,
    required this.round,
    required this.eventOrdinal,
    required this.publicScores,
    required this.ownGoods,
    required this.ownCards,
    required this.legalActions,
    required this.actionsSinceRoll,
  });

  final int seat, activeSeat, round, eventOrdinal, actionsSinceRoll;
  final MatchPhase phase;
  final List<int> publicScores;
  final Map<Resource, int> ownGoods;
  final List<HeldCard> ownCards;
  final List<MatchEvent> legalActions;
  final int _seed;
}

/// Pure engine-facing AI adapter. It is intentionally a finite *subset* of
/// legal actions: the engine permits unbounded offer quantities, and stealing a
/// particular good requires knowledge of an opponent's private inventory.
///
/// The host still applies selected events through MatchEngine.apply. The AI
/// cannot act for a different seat or reuse a stale observation.
abstract final class AiActionAdapter {
  static AiTurnView observe(MatchState state, int seat) {
    RangeError.checkValidIndex(seat, state.players, 'seat');
    final expected = state.tactical?.responder ?? state.active;
    if (seat != expected) {
      throw StateError('AI may observe only the acting/responding seat.');
    }

    final actions = <MatchEvent>[];
    if (state.tactical case final TacticalWindow window) {
      actions.add(RespondTactical(window.id, seat, TacticalChoice.pass));
      if (window.kind == TacticalKind.bandit &&
          MatchEngine.canIntercept(state, seat)) {
        actions.add(RespondTactical(window.id, seat, TacticalChoice.intercept));
      }
      if (window.kind == TacticalKind.governance) {
        for (final index in MatchEngine.counterCards(
          state,
          seat,
          window.card!,
        )) {
          actions.add(
            RespondTactical(
              window.id,
              seat,
              TacticalChoice.counter,
              cardIndex: index,
            ),
          );
        }
      }
      if (window.kind == TacticalKind.invasion &&
          MatchEngine.canAid(state, seat)) {
        for (final good in [Resource.wheat, Resource.ore]) {
          if ((state.players[seat].stores[good] ?? 0) > 0) {
            actions.add(
              RespondTactical(window.id, seat, TacticalChoice.aid, good: good),
            );
          }
        }
      }
    } else {
      switch (state.phase) {
        case MatchPhase.setupVillage:
          actions.addAll(
            MatchEngine.legalVertices(state).map(PlaceVillage.new),
          );
        case MatchPhase.setupRoad:
          actions.addAll(MatchEngine.legalEdges(state).map(PlaceRoad.new));
        case MatchPhase.roll:
          final (first, second) = MatchEngine.expectedDice(state);
          actions.add(RollDice(first, second));
        case MatchPhase.bandit:
          // A null victim is always legal. Choosing a particular victim would
          // require consulting their concealed resource inventory.
          for (var tile = 0; tile < state.board.tiles.length; tile++) {
            if (tile != state.banditTile) {
              actions.add(MoveBandit(tile));
            }
          }
        case MatchPhase.invasion:
          actions.add(const ResolveInvasion());
        case MatchPhase.actions:
          _actionPhase(state, actions);
        case MatchPhase.finished:
          break;
      }
    }

    // Preserve enumeration order, de-duplicating by canonical replay payload.
    final distinct = <String, MatchEvent>{};
    for (final action in actions) {
      distinct.putIfAbsent(jsonEncode(action.toJson()), () => action);
    }
    final player = state.players[seat];
    return AiTurnView._(
      state.seed,
      seat: seat,
      phase: state.phase,
      activeSeat: state.active,
      round: state.round,
      eventOrdinal: state.events.length,
      publicScores: List.unmodifiable([
        for (var i = 0; i < state.players.length; i++)
          MatchEngine.score(state, i),
      ]),
      ownGoods: Map.unmodifiable(player.stores),
      ownCards: List.unmodifiable(player.cards),
      legalActions: List.unmodifiable(distinct.values),
      actionsSinceRoll: _actionsSinceRoll(state),
    );
  }

  static void _actionPhase(MatchState s, List<MatchEvent> actions) {
    for (final vertex in MatchEngine.legalVertices(s)) {
      actions.add(PlaceVillage(vertex));
    }
    for (final edge in MatchEngine.legalEdges(s)) {
      actions.add(PlaceRoad(edge));
    }
    for (final vertex in MatchEngine.legalUpgrades(s)..sort()) {
      actions.add(UpgradeSite(vertex));
    }
    for (final track in StrategyDeck.values) {
      if (MatchEngine.canDevelop(s, track)) actions.add(DevelopTown(track));
    }
    for (final vertex in s.sites.keys.toList()..sort()) {
      if (MatchEngine.legalFort(s, vertex)) {
        actions.add(FortifyTown(vertex));
      }
    }
    for (var vertex = 0; vertex < s.topology.vertices.length; vertex++) {
      if (MatchEngine.legalRecruit(s, vertex)) {
        actions.add(RecruitKnight(vertex));
      }
    }
    for (final from in s.knights.keys.toList()..sort()) {
      if (MatchEngine.legalActivate(s, from)) actions.add(ActivateKnight(from));
      if (MatchEngine.legalPromote(s, from)) actions.add(PromoteKnight(from));
      for (final to in MatchEngine.legalKnightDestinations(s, from)) {
        actions.add(MoveKnight(from, to));
      }
    }
    for (var i = 0; i < s.current.cards.length; i++) {
      // Unlike other powers, seizeGood legality checks a rival's hidden
      // inventory. Do not ask the engine for its targets in this adapter.
      if (s.current.cards[i].definition.power != CardPower.seizeGood) {
        actions.addAll(MatchEngine.legalCardPlays(s, i));
      }
      // Unplayable cards never hold the AI's turn hostage.
      actions.add(DiscardStrategyCard(i));
    }

    final rate = MatchEngine.tradeRate(s, s.active);
    final commerce = s.current.level(StrategyDeck.commerce);
    for (final give in Resource.values) {
      if ((s.current.stores[give] ?? 0) < rate) continue;
      for (final receive in Resource.values) {
        if (receive == give) continue;
        final count = commerce >= 5
            ? s.balance.bazaarGoods
            : commerce >= 3 && receive == Resource.cloth
            ? 2
            : 1;
        if ((s.bank[receive] ?? 0) >= count) {
          actions.add(BankExchange(give, receive));
        }
      }
    }

    for (final offer in s.offers) {
      if (offer.target == s.active) {
        actions.add(RespondTrade(s.active, false, offerId: offer.id));
        if ((s.current.stores[offer.want] ?? 0) >= offer.wantCount) {
          actions.add(RespondTrade(s.active, true, offerId: offer.id));
        }
      }
      if (offer.proposer == s.active) {
        actions.add(WithdrawTrade(offer.id));
      }
    }

    if (!s.offers.any((o) => o.proposer == s.active)) {
      // The reducer accepts arbitrary positive requested amounts; 1-for-1
      // proposals are a finite, public-information-only AI candidate policy.
      for (final give in Resource.values) {
        if ((s.current.stores[give] ?? 0) < 1) continue;
        for (final want in Resource.values) {
          if (give == want) continue;
          for (var target = 0; target < s.players.length; target++) {
            if (target == s.active) continue;
            actions.add(ProposeTrade(target, give, 1, want, 1));
          }
        }
      }
    }
    actions.add(const EndTurn());
  }

  static int _actionsSinceRoll(MatchState s) {
    var count = 0;
    for (final event in s.events.reversed) {
      if (event is RollDice || event is EndTurn) break;
      count++;
    }
    return count;
  }

  static int _mix(int value) {
    var x = value & 0xffffffff;
    if (x == 0) x = 0x6d2b79f5;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    return x & 0xffffffff;
  }

  /// Decision depends solely on saved match seed, seat, event ordinal and
  /// that seat's options. No wall-clock, global Random or mutable RNG cursor.
  /// At most eight post-roll events are selected before End Turn is forced.
  static MatchEvent? decide(AiTurnView view) {
    if (view.legalActions.isEmpty) return null;
    final key = _mix(
      view._seed ^
          ((view.seat + 1) * 0x9e3779b9) ^
          (view.eventOrdinal * 0x85ebca6b),
    );
    if (view.phase == MatchPhase.actions) {
      final end = view.legalActions.whereType<EndTurn>().first;
      if (view.actionsSinceRoll >= 8 || key % 5 == 0) return end;
      final other = view.legalActions.where((e) => e is! EndTurn).toList();
      return other.isEmpty ? end : other[key % other.length];
    }
    return view.legalActions[key % view.legalActions.length];
  }

  /// Rechecks observation freshness and whitelist membership at dispatch.
  static MatchState applySelected(
    MatchState state,
    AiTurnView view,
    MatchEvent action,
  ) {
    if (state.seed != view._seed ||
        state.events.length != view.eventOrdinal ||
        state.active != view.activeSeat ||
        state.phase != view.phase ||
        (state.tactical?.responder ?? state.active) != view.seat) {
      throw StateError('AI observation is stale or belongs to another seat.');
    }
    final key = jsonEncode(action.toJson());
    if (!view.legalActions.any((e) => jsonEncode(e.toJson()) == key)) {
      throw StateError('AI selected an action outside its legal options.');
    }
    return MatchEngine.apply(state, action);
  }
}
