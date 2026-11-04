import 'dart:convert';

import 'advanced.dart';
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
    required this.strategy,
  });

  final int seat, activeSeat, round, eventOrdinal, actionsSinceRoll;
  final MatchPhase phase;
  final List<int> publicScores;
  final Map<Resource, int> ownGoods;
  final List<HeldCard> ownCards;
  final List<MatchEvent> legalActions;
  final int _seed;
  final AiStrategySignals strategy;
}

/// Public and own-seat signals for advanced planning. No opponent's stores,
/// cards, private deck order, or future rolls cross this boundary.
class AiStrategySignals {
  const AiStrategySignals({
    required this.season,
    required this.pressure,
    required this.invasionThreat,
    required this.sharedDefence,
    required this.invasionAid,
    required this.aidRespondersRemaining,
    required this.scoreDeficit,
    required this.dryRolls,
    required this.reliefUsed,
    required this.tradeRate,
    required this.ownSites,
    required this.ownKnights,
    required this.publicKnights,
    required this.fortified,
    required this.levels,
    required this.productionPips,
    required this.bankStock,
  });

  final int season, pressure, invasionThreat, sharedDefence, invasionAid;
  final int aidRespondersRemaining, scoreDeficit, dryRolls, tradeRate;
  final bool reliefUsed;
  final Map<int, Structure> ownSites;
  final Map<int, KnightPiece> ownKnights, publicKnights;
  final Set<int> fortified;
  final Map<StrategyDeck, int> levels, productionPips;
  final Map<Resource, int> bankStock;
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
      strategy: _strategySignals(state, seat),
    );
  }

  static AiStrategySignals _strategySignals(MatchState state, int seat) {
    const pips = <int, int>{
      2: 1,
      3: 2,
      4: 3,
      5: 4,
      6: 5,
      8: 5,
      9: 4,
      10: 3,
      11: 2,
      12: 1,
    };
    final ownSites = <int, Structure>{};
    final production = {for (final track in StrategyDeck.values) track: 0};
    for (final entry in state.sites.entries) {
      if (entry.value.owner != seat) continue;
      ownSites[entry.key] = entry.value.structure;
      if (entry.value.structure == Structure.village) continue;
      for (final tile in state.topology.vertices[entry.key].tiles) {
        if (tile == state.banditTile) continue;
        final land = state.board.tiles[tile].land;
        final number = state.board.tiles[tile].productionNumber;
        for (final track in StrategyDeck.values) {
          if (track.sourceLand == land) {
            production[track] = production[track]! + (pips[number] ?? 0);
          }
        }
      }
    }
    final ownKnights = <int, KnightPiece>{
      for (final entry in state.knights.entries)
        if (entry.value.owner == seat) entry.key: entry.value,
    };
    final scores = <int>[];
    for (var i = 0; i < state.players.length; i++) {
      scores.add(MatchEngine.score(state, i));
    }
    final best = scores.reduce((a, b) => a > b ? a : b);
    return AiStrategySignals(
      // Three complete rounds per season; no assumed production multiplier.
      season: ((state.round - 1) ~/ 3) % 4,
      pressure: state.reaverPressure,
      invasionThreat: MatchEngine.invasionStrength(state),
      sharedDefence: MatchEngine.defenceStrength(state),
      invasionAid: state.invasionAid,
      aidRespondersRemaining: (state.tactical?.responders.length ?? 1) - 1,
      scoreDeficit: best - scores[seat],
      dryRolls: state.dryRolls[seat] ?? 0,
      reliefUsed: state.reliefUsed.contains(seat),
      tradeRate: MatchEngine.tradeRate(state, seat),
      ownSites: Map.unmodifiable(ownSites),
      ownKnights: Map.unmodifiable(ownKnights),
      publicKnights: Map.unmodifiable(state.knights),
      fortified: Set.unmodifiable(state.fortified),
      levels: Map.unmodifiable({
        for (final track in StrategyDeck.values)
          track: state.players[seat].level(track),
      }),
      productionPips: Map.unmodifiable(production),
      bankStock: Map.unmodifiable(state.bank),
    );
  }

  static T? _first<T extends MatchEvent>(AiTurnView view) {
    for (final action in view.legalActions) {
      if (action is T) return action;
    }
    return null;
  }

  /// A bounded, replay-safe advanced policy; all candidates are from the
  /// adapter whitelist, so finite bank stock and legality stay in the reducer.
  static MatchEvent? advancedDecision(AiTurnView view) {
    final s = view.strategy;
    final actions = view.legalActions;
    if (view.phase == MatchPhase.finished) return null;
    if (view.phase == MatchPhase.actions && view.actionsSinceRoll >= 8) {
      return _first<EndTurn>(view);
    }

    final tactical = _first<RespondTactical>(view);
    if (tactical != null) {
      final counter = actions.whereType<RespondTactical>().where(
        (a) =>
            a.choice == TacticalChoice.counter ||
            a.choice == TacticalChoice.intercept,
      );
      if (counter.isNotEmpty) return counter.first;
      final gap = s.invasionThreat - s.sharedDefence - s.invasionAid;
      final aid = actions
          .whereType<RespondTactical>()
          .where((a) => a.choice == TacticalChoice.aid)
          .toList();
      if (gap > 0 && aid.isNotEmpty) {
        // Unknown future responders' hands are NOT inspected. Use only the
        // upper bound of two aid per public remaining respondent.
        final ownMaximum = aid.any((a) => a.good == Resource.ore) ? 2 : 1;
        final feasible = gap <= ownMaximum + s.aidRespondersRemaining * 2;
        if (feasible) {
          if (gap == 1) {
            for (final a in aid) {
              if (a.good == Resource.wheat) return a;
            }
          }
          for (final a in aid) {
            if (a.good == Resource.ore) return a;
          }
          return aid.first;
        }
      }
      return tactical; // The first tactical choice is the legal Pass.
    }
    if (view.phase != MatchPhase.actions) return null;

    final upgrades = actions.whereType<UpgradeSite>().toList();
    for (final a in upgrades) {
      if (s.ownSites[a.vertex] == Structure.town) return a;
    }
    final village = _first<PlaceVillage>(view);
    if (village != null) return village;
    if (upgrades.isNotEmpty) return upgrades.first;

    final gap = s.invasionThreat - s.sharedDefence;
    final impending = s.pressure >= 2 && gap > 0;
    final activates = actions.whereType<ActivateKnight>().toList();
    final promotes = actions.whereType<PromoteKnight>().toList();
    final forts = actions.whereType<FortifyTown>().toList();
    final recruits = actions.whereType<RecruitKnight>().toList();
    if (impending) {
      if (activates.isNotEmpty) return activates.first;
      // Forts both strengthen defence and absorb a failed invasion hit.
      if (forts.isNotEmpty) return forts.first;
      if (promotes.isNotEmpty) return promotes.first;
      // Recruits cannot activate in their recruitment turn.
      if (s.pressure == 2 && recruits.isNotEmpty) return recruits.first;
    }

    final development = actions.whereType<DevelopTown>().toList();
    double developValue(DevelopTown a) {
      final level = s.levels[a.track] ?? 0;
      final production = s.productionPips[a.track] ?? 0;
      if (level == 0) {
        return 4 +
            production * 0.8 +
            (a.track == StrategyDeck.commerce ? 2 : 0);
      }
      if (a.track == StrategyDeck.commerce && level == 1) return 20;
      if (a.track == StrategyDeck.governance &&
          level == 1 &&
          s.pressure >= 2 &&
          gap > 0) {
        return 24;
      }
      if (a.track == StrategyDeck.innovation &&
          level == 2 &&
          s.scoreDeficit >= 3 &&
          s.dryRolls > 0 &&
          !s.reliefUsed) {
        return 22;
      }
      if (a.track == StrategyDeck.innovation &&
          level == 3 &&
          s.scoreDeficit >= 3 &&
          !s.reliefUsed) {
        return 18;
      }
      if (a.track == StrategyDeck.commerce && level == 3) return 17;
      if (a.track == StrategyDeck.governance &&
          level == 4 &&
          s.pressure >= 2 &&
          gap > 0) {
        return 17;
      }
      return production > 0 ? 6 + production * 0.4 : 1;
    }

    if (development.isNotEmpty) {
      development.sort((a, b) {
        final result = developValue(b).compareTo(developValue(a));
        return result != 0 ? result : a.track.index.compareTo(b.track.index);
      });
      if (developValue(development.first) >= 6) return development.first;
    }

    // Recover construction deficits via *actual* stock-backed bank trades.
    // Preserve goods already needed for the next reachable VP upgrade.
    final goal = s.ownSites.values.contains(Structure.town)
        ? MatchEngine.capitalCost
        : s.ownSites.values.contains(Structure.village)
        ? MatchEngine.townCost
        : MatchEngine.villageCost;
    final exchanges = actions.whereType<BankExchange>().where((a) {
      final deficit = (goal[a.receive] ?? 0) - (view.ownGoods[a.receive] ?? 0);
      final spare = (view.ownGoods[a.give] ?? 0) - (goal[a.give] ?? 0);
      return deficit > 0 &&
          spare >= s.tradeRate &&
          (s.bankStock[a.receive] ?? 0) > 0;
    }).toList();
    if (exchanges.isNotEmpty) {
      exchanges.sort((a, b) {
        final aDeficit =
            (goal[a.receive] ?? 0) - (view.ownGoods[a.receive] ?? 0);
        final bDeficit =
            (goal[b.receive] ?? 0) - (view.ownGoods[b.receive] ?? 0);
        final result = bDeficit.compareTo(aDeficit);
        return result != 0
            ? result
            : (a.give.index * 8 + a.receive.index).compareTo(
                b.give.index * 8 + b.receive.index,
              );
      });
      return exchanges.first;
    }

    // Movement has strategic value only if it displaces a weaker rival.
    // Empty-junction shuffling can burn turns without adding defence.
    final displacements = actions
        .whereType<MoveKnight>()
        .where(
          (a) =>
              s.publicKnights.containsKey(a.to) &&
              s.publicKnights[a.to]!.owner != view.seat,
        )
        .toList();
    if (displacements.isNotEmpty) {
      displacements.sort((a, b) {
        final rank = s.publicKnights[b.to]!.rank.strength.compareTo(
          s.publicKnights[a.to]!.rank.strength,
        );
        return rank != 0 ? rank : a.to.compareTo(b.to);
      });
      return displacements.first;
    }
    // Keep development and military investment bounded and leave the
    // lower-level draft/road/card selection to the existing policy.
    return null;
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
    final advanced = advancedDecision(view);
    if (advanced != null) return advanced;
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
