import 'dart:math' as math;

import 'ai.dart';
import 'ai_cards.dart';
import 'board.dart';
import 'game.dart';
import 'match.dart';

/// Older saves default to Hard.
enum BotDifficulty {
  easy('Easy', 2),
  medium('Medium', 4),
  hard('Hard', 8);

  const BotDifficulty(this.label, this.actionLimit);
  final String label;
  final int actionLimit;

  static BotDifficulty parse(Object? value) => values.firstWhere(
    (difficulty) => difficulty.name == value,
    orElse: () => hard,
  );
}

/// Exposes only actions validated by the pure match engine. The bot never
/// invents placements, exchanges or dice outcomes.
class AiLegalActions {
  AiLegalActions(MatchState state)
    : _options = AiActionAdapter.observe(state, state.actingSeat).legalActions;

  // The adapter is the authoritative whitelist. No opponent hand queries,
  // speculative reducer events or private target checks are done here.
  final List<MatchEvent> _options;

  List<PlaceVillage> get villages =>
      _options.whereType<PlaceVillage>().toList();
  List<PlaceRoad> get roads => _options.whereType<PlaceRoad>().toList();
  List<UpgradeSite> get upgrades => _options.whereType<UpgradeSite>().toList();
  List<DevelopTown> get developments =>
      _options.whereType<DevelopTown>().toList();
  List<BankExchange> get exchanges =>
      _options.whereType<BankExchange>().toList();
  List<PlayStrategyCard> get cards =>
      _options.whereType<PlayStrategyCard>().toList();
  List<RecruitGuard> get recruits =>
      _options.whereType<RecruitGuard>().toList();
  List<MoveGuard> get guardMoves => _options.whereType<MoveGuard>().toList();
  List<ActivateGuard> get activates =>
      _options.whereType<ActivateGuard>().toList();
  List<PromoteGuard> get promotions =>
      _options.whereType<PromoteGuard>().toList();
  List<FortifyTown> get fortifications =>
      _options.whereType<FortifyTown>().toList();
  List<MoveBandit> get banditMoves => _options.whereType<MoveBandit>().toList();
  List<RespondTactical> get tactical =>
      _options.whereType<RespondTactical>().toList();
}

/// A stateless, deterministic offline opponent. Every call selects one legal
/// event; applying it remains the responsibility of MatchEngine.apply.
///
/// Reads the public board, scores and own hand only. Opponent hands, cards and
/// future events are deliberately excluded from scoring.
class HeuristicAi {
  const HeuristicAi({
    this.track = StrategyDeck.commerce,
    this.difficulty = BotDifficulty.hard,
  });

  final BotDifficulty difficulty;

  final StrategyDeck track;

  static const _pips = <int, int>{
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

  int _have(MatchState state, Resource good) => state.current.stores[good] ?? 0;

  bool _open(MatchState state, int vertex) =>
      !state.sites.containsKey(vertex) &&
      !state.topology.neighbours(vertex).any(state.sites.containsKey);

  /// Expected per-roll production, including complementarity with our own
  /// villages. Tile numbers and terrain are public and dice probabilities
  /// require no hidden information or lookahead.
  double siteValue(MatchState state, int vertex) {
    final output = {for (final r in Resource.values.take(5)) r: 0.0};
    final numbers = <int>{};
    for (final entry in state.sites.entries) {
      if (entry.value.owner != state.active) continue;
      for (final tile in state.topology.vertices[entry.key].tiles) {
        final hex = state.board.tiles[tile];
        final good = hex.land.produces;
        if (good == null || hex.productionNumber == null) continue;
        output[good] =
            output[good]! +
            (_pips[hex.productionNumber] ?? 0) *
                (entry.value.structure == Structure.village ? 1 : 2);
        numbers.add(hex.productionNumber!);
      }
    }

    var value = 0.0;
    final localGoods = <Resource>{};
    final localNumbers = <int>{};
    for (final tile in state.topology.vertices[vertex].tiles) {
      final hex = state.board.tiles[tile];
      final good = hex.land.produces;
      final number = hex.productionNumber;
      if (good == null || number == null) continue;
      final pips = (_pips[number] ?? 0).toDouble();
      final base = switch (good) {
        Resource.wheat => 1.26,
        Resource.ore => 1.22,
        Resource.wood || Resource.brick => 1.08,
        _ => 1.0,
      };
      final scarcity = 1.0 + 0.32 / (1.0 + output[good]! / 5);
      final variety = numbers.contains(number) ? 0.94 : 1.05;
      final unblocked = tile == state.banditTile ? 0.65 : 1.0;
      value += pips * base * scarcity * variety * unblocked;
      localGoods.add(good);
      localNumbers.add(number);
    }
    // Diverse outputs beat a superficially similar, concentrated site.
    value += localGoods.length * 0.34 + localNumbers.length * 0.15;
    return value;
  }

  T _best<T>(Iterable<T> items, double Function(T) value, int Function(T) id) {
    final sorted = items.toList()
      ..sort((a, b) {
        final quality = value(b).compareTo(value(a));
        return quality != 0 ? quality : id(a).compareTo(id(b));
      });
    // Lower levels consider a small band of good choices, without selecting
    // arbitrary legal moves. The index is stable across repeated decisions.
    final rank = switch (difficulty) {
      BotDifficulty.easy => 2,
      BotDifficulty.medium => 1,
      BotDifficulty.hard => 0,
    };
    return sorted[math.min(rank, sorted.length - 1)];
  }

  // Stable variety keeps replays deterministic while varying aggressive turns.
  bool _aggressive(MatchState state) =>
      (state.seed + state.turnSerial * 17 + state.active * 31) % 100 < 40;

  double _blockingValue(MatchState state, int vertex) {
    final junction = state.topology.vertices[vertex];
    var value = 0.0;
    for (var seat = 0; seat < state.players.length; seat++) {
      if (seat == state.active) continue;
      final roads = junction.edges.where((e) => state.roads[e] == seat).length;
      if (roads >= 2) value += 9;
      if (roads == 1) value += 3;
    }
    return value;
  }

  double _guardValue(MatchState state, int vertex) {
    final junction = state.topology.vertices[vertex];
    final ownRoads = junction.edges
        .where((e) => state.roads[e] == state.active)
        .length;
    // Guard contested junctions without occupying our best village sites.
    return _blockingValue(state, vertex) * 2 +
        ownRoads * 1.5 -
        (_open(state, vertex) ? siteValue(state, vertex) * .8 : 0);
  }

  double _roadValue(MatchState state, int edge) {
    final road = state.topology.edges[edge];
    final accessible = <int>{};
    for (final entry in state.roads.entries) {
      if (entry.value != state.active) continue;
      final existing = state.topology.edges[entry.key];
      accessible.add(existing.a);
      accessible.add(existing.b);
    }
    final endpoints = [road.a, road.b];
    var best = 0.0;
    for (final vertex in endpoints) {
      if (_open(state, vertex) && !accessible.contains(vertex)) {
        best = math.max(best, siteValue(state, vertex));
      }
      for (final next in state.topology.neighbours(vertex)) {
        // Do not route through a rival village.
        if (state.sites[vertex]?.owner != null &&
            state.sites[vertex]!.owner != state.active) {
          continue;
        }
        if (_open(state, next) && !accessible.contains(next)) {
          best = math.max(best, siteValue(state, next) * 0.72);
        }
      }
    }
    return best +
        (_aggressive(state)
            ? endpoints
                  .map((v) => _blockingValue(state, v))
                  .fold<double>(0, math.max)
            : 0);
  }

  Map<Resource, int> _goal(MatchState state) {
    // Build towards a *geometrically possible* score, not arbitrary goods.
    final canVillage = state.topology.vertices.any(
      (v) =>
          _open(state, v.id) &&
          v.edges.any((e) => state.roads[e] == state.active),
    );
    if (canVillage) return MatchEngine.villageCost;
    final own = state.sites.entries
        .where((entry) => entry.value.owner == state.active)
        .toList();
    if (own.any((entry) => entry.value.structure == Structure.village)) {
      return MatchEngine.townCost;
    }
    if (own.any((entry) => entry.value.structure == Structure.town)) {
      return MatchEngine.capitalCost;
    }
    return MatchEngine.villageCost;
  }

  BankExchange? _exchange(MatchState state, AiLegalActions legal) {
    final goal = _goal(state);
    final rate = MatchEngine.tradeRate(state, state.active);
    final choices = legal.exchanges.where((event) {
      final deficit = (goal[event.receive] ?? 0) - _have(state, event.receive);
      final spare = _have(state, event.give) - (goal[event.give] ?? 0);
      return deficit > 0 && spare >= rate;
    }).toList();
    if (choices.isEmpty) return null;
    // Never trade repeatedly just to shuffle a surplus: one conversion per
    // action turn, unless a single engine event fulfils a different goal.
    for (final event in state.events.reversed) {
      if (event is RollDice || event is EndTurn) break;
      if (event is BankExchange) return null;
    }
    return _best<BankExchange>(
      choices,
      (event) =>
          ((goal[event.receive] ?? 0) - _have(state, event.receive)) * 10.0 +
          (_have(state, event.give) - (goal[event.give] ?? 0)) * 0.2,
      (event) => event.give.index * 8 + event.receive.index,
    );
  }

  MoveBandit _bandit(MatchState state, AiLegalActions legal) =>
      _best<MoveBandit>(legal.banditMoves, (event) {
        final tile = state.board.tiles[event.tile];
        final scores = [
          for (var i = 0; i < state.players.length; i++)
            if (i != state.active) MatchEngine.score(state, i),
        ];
        final leaderScore = scores.reduce(math.max);
        var value = 0.0;
        // Bots pressure the leader, not whichever neighbour joined first.
        if (event.victim != null && event.victim != state.active) {
          final targetScore = MatchEngine.score(state, event.victim!);
          value += targetScore == leaderScore ? 100 : targetScore * 3;
        }

        for (final vertex in state.topology.tileVertices[event.tile]) {
          final site = state.sites[vertex];
          if (site == null) continue;
          final weight =
              (site.structure.points + 1) * (_pips[tile.productionNumber] ?? 0);
          value += site.owner == state.active
              ? -weight * 2.2
              : weight * (1 + MatchEngine.score(state, site.owner) / 8);
        }
        return value;
      }, (event) => event.tile * 4 + (event.victim ?? 0));

  MatchEvent _tactical(MatchState state, AiLegalActions legal) {
    final view = AiActionAdapter.observe(state, state.tactical!.responder);
    return AiCardStrategy.tactical(view) ??
        AiActionAdapter.advancedDecision(view) ??
        legal.tactical.first;
  }

  MatchEvent? choose(MatchState state) {
    if (state.phase == MatchPhase.finished) return null;
    if (state.pendingDiscards.isNotEmpty) {
      return AiActionAdapter.observe(
        state,
        state.actingSeat,
      ).legalActions.single;
    }
    final legal = AiLegalActions(state);
    if (state.tactical != null) return _tactical(state, legal);
    switch (state.phase) {
      case MatchPhase.setupVillage:
        return _best<PlaceVillage>(
          legal.villages,
          (e) => siteValue(state, e.vertex),
          (e) => e.vertex,
        );
      case MatchPhase.setupRoad:
        return _best<PlaceRoad>(
          legal.roads,
          (e) => _roadValue(state, e.edge),
          (e) => e.edge,
        );
      case MatchPhase.roll:
        final (a, b) = MatchEngine.expectedDice(state);
        return RollDice(a, b);
      case MatchPhase.bandit:
        return _bandit(state, legal);
      case MatchPhase.invasion:
        return const ResolveInvasion();
      case MatchPhase.actions:
        return _action(state, legal);
      case MatchPhase.finished:
        return null;
    }
  }

  RespondTrade answerOffer(MatchState state, int seat, TradeProposal offer) {
    final responding = state.copyWith(active: seat, offers: [offer]);
    final view = AiActionAdapter.observe(responding, seat);
    final hard = difficulty == BotDifficulty.hard;
    final answer = AiCardStrategy.incomingOffer(
      view,
      goal: hard ? _hardGoal(responding) : null,
      cautious: hard,
    );
    return answer is RespondTrade
        ? answer
        : RespondTrade(seat, false, offerId: offer.id);
  }

  List<ProposeTrade> _recentRejectedOffers(MatchState state) {
    final rejected = <int>{};
    final accepted = <int>{};
    final result = <ProposeTrade>[];
    var actor = state.active;
    var turns = 0;
    for (var i = state.events.length - 1; i >= 0; i--) {
      final event = state.events[i];
      if (event is EndTurn) {
        turns++;
        if (turns > state.players.length * 2) break;
        final order = state.turnOrder;
        actor = order[(order.indexOf(actor) - 1 + order.length) % order.length];
      } else if (event is RespondTrade && event.offerId != null) {
        (event.accept ? accepted : rejected).add(event.offerId!);
      } else if (event is ProposeTrade &&
          event.counterOf == null &&
          actor == state.active &&
          rejected.contains(i) &&
          !accepted.contains(i)) {
        result.add(event);
      }
    }
    return result;
  }

  // A construction plan reserves the same goods for bank, player trades and
  // development. Only public geometry and our own hand enter this decision.
  double _hardRoadValue(MatchState state, int edgeId) {
    final edge = state.topology.edges[edgeId];
    bool open(int v) => _open(state, v) && !state.guards.containsKey(v);
    bool blocked(int v) =>
        (state.sites[v] != null && state.sites[v]!.owner != state.active) ||
        (state.guards[v] != null && state.guards[v]!.owner != state.active);
    bool connected(int v) => state.topology.vertices[v].edges.any(
      (e) => state.roads[e] == state.active,
    );
    var best = 0.0;
    for (final v in [edge.a, edge.b]) {
      if (connected(v) || blocked(v)) continue;
      if (open(v)) best = math.max(best, siteValue(state, v));
      for (final nextEdge in state.topology.vertices[v].edges) {
        if (nextEdge == edgeId || state.roads.containsKey(nextEdge)) continue;
        final next = state.topology.edges[nextEdge];
        final target = next.a == v ? next.b : next.a;
        if (open(target) && !connected(target)) {
          best = math.max(best, siteValue(state, target) * .65);
        }
      }
    }
    return best;
  }

  Map<Resource, int> _hardGoal(MatchState state) {
    final own = state.sites.entries.where((e) => e.value.owner == state.active);
    final goals = <(Map<Resource, int>, double)>[];
    bool open(int v) => _open(state, v) && !state.guards.containsKey(v);
    final reachable = state.topology.vertices.where(
      (v) => open(v.id) && v.edges.any((e) => state.roads[e] == state.active),
    );
    if (reachable.isNotEmpty) {
      final quality = reachable
          .map((v) => siteValue(state, v.id))
          .reduce(math.max);
      goals.add((MatchEngine.villageCost, 7 + quality * .35));
    }
    for (final site in own) {
      final quality = siteValue(state, site.key);
      if (site.value.structure == Structure.village) {
        goals.add((
          state.reaverScars.contains(site.key)
              ? MatchEngine.rebuildCost
              : MatchEngine.townCost,
          9 +
              quality * .35 +
              (own.any((e) => e.value.structure != Structure.village) ? 0 : 5),
        ));
      } else if (site.value.structure == Structure.town) {
        goals.add((MatchEngine.capitalCost, 13 + quality * .15));
      }
    }
    if (reachable.isEmpty &&
        state.roads.values.where((p) => p == state.active).length <
            MatchEngine.roadLimit) {
      bool linked(int v) {
        if (state.guards[v] case final guard?
            when guard.owner != state.active) {
          return false;
        }
        if (state.sites[v] case final site?) return site.owner == state.active;
        return state.topology.vertices[v].edges.any(
          (e) => state.roads[e] == state.active,
        );
      }

      final roads = state.topology.edges.where(
        (e) => !state.roads.containsKey(e.id) && (linked(e.a) || linked(e.b)),
      );
      if (roads.isNotEmpty) {
        final quality = roads
            .map((e) => _hardRoadValue(state, e.id))
            .reduce(math.max);
        if (quality >= 3) {
          goals.add((MatchEngine.effectiveRoadCost(state), 5 + quality * .35));
        }
      }
    }
    if (goals.isEmpty) return MatchEngine.villageCost;
    double value((Map<Resource, int>, double) plan) {
      final deficit = plan.$1.entries.fold<int>(
        0,
        (n, e) => n + math.max(0, e.value - _have(state, e.key)),
      );
      return plan.$2 - deficit * 1.5;
    }

    goals.sort((a, b) => value(b).compareTo(value(a)));
    return goals.first.$1;
  }

  BankExchange? _hardExchange(
    MatchState state,
    AiLegalActions legal,
    Map<Resource, int> goal,
  ) {
    final prior = state.events.reversed
        .takeWhile((e) => e is! RollDice && e is! EndTurn)
        .whereType<BankExchange>()
        .toList();
    if (prior.length >= 2) return null;
    final commerce = state.current.level(StrategyDeck.commerce);
    double gain(BankExchange e) {
      final missing = (goal[e.receive] ?? 0) - _have(state, e.receive);
      final rate = MatchEngine.tradeRate(state, state.active, e.give);
      final surplus = _have(state, e.give) - (goal[e.give] ?? 0);
      if (missing <= 0 ||
          surplus < rate ||
          prior.any((p) => p.give == e.receive)) {
        return -100;
      }
      final received = commerce >= 5
          ? state.balance.bazaarGoods
          : commerce >= 3 && e.receive == Resource.cloth
          ? 2
          : 1;
      return math.min(missing, received) * 10.0 -
          rate * 1.5 +
          missing * .2 +
          surplus * .05;
    }

    final candidates = legal.exchanges.where((e) => gain(e) > 0).toList();
    if (candidates.isEmpty) return null;
    return _best<BankExchange>(
      candidates,
      gain,
      (e) => e.give.index * 8 + e.receive.index,
    );
  }

  MatchEvent _action(MatchState state, AiLegalActions legal) {
    final view = AiActionAdapter.observe(state, state.active);
    if (view.actionsSinceRoll >= difficulty.actionLimit) return const EndTurn();
    final hard = difficulty == BotDifficulty.hard;
    final goal = hard ? _hardGoal(state) : null;
    // Never sacrifice an immediate winning construction action for shared defence.
    if (hard) {
      final score = MatchEngine.score(state, state.active);
      for (final upgrade in legal.upgrades) {
        final points = state.sites[upgrade.vertex]!.structure == Structure.town
            ? 2
            : 1;
        if (score + points >= GameEngine.winningPoints) return upgrade;
      }
      if (score + 1 >= GameEngine.winningPoints && legal.villages.isNotEmpty) {
        return legal.villages.first;
      }
    }

    final answer = AiCardStrategy.incomingOffer(
      view,
      goal: goal,
      cautious: hard,
    );
    if (answer != null) return answer;

    // Defend before all ore is sunk into points: a Guard needs a recruitment
    // turn and a later activation, so reacting at invasion time is too late.
    final ownGuards = state.guards.entries
        .where((entry) => entry.value.owner == state.active)
        .toList();
    final approachingFleet = MatchEngine.invasionStrength(state);
    final needDefence = MatchEngine.defenceStrength(state) < approachingFleet;
    final roundsUntilRaid = state.raidInterval - state.reaverPressure;
    final ownsTown = state.sites.values.any(
      (site) =>
          site.owner == state.active && site.structure != Structure.village,
    );
    final rivalTowns = state.sites.values.any(
      (site) =>
          site.owner != state.active && site.structure != Structure.village,
    );
    // A player with no towns at risk can profit from an undefended invasion.
    final defend = ownsTown || !rivalTowns;
    // Earlier defence is worthwhile if it does not delay a scoring build.
    // Near the raid, protect the board even when construction is possible.
    final urgent = roundsUntilRaid <= 2;
    final canBuild = legal.villages.isNotEmpty || legal.upgrades.isNotEmpty;
    if (defend &&
        needDefence &&
        view.actionsSinceRoll < 6 &&
        (!hard || urgent || !canBuild)) {
      if (legal.activates.isNotEmpty) {
        return _best<ActivateGuard>(
          legal.activates,
          (event) => state.guards[event.vertex]!.rank.strength.toDouble(),
          (event) => event.vertex,
        );
      }
      final promotions = hard && !urgent && ownGuards.length > 1
          ? legal.promotions
                .where(
                  (e) => MatchEngine.promotionCost(state.guards[e.vertex]!.rank)
                      .entries
                      .every(
                        (cost) =>
                            _have(state, cost.key) - cost.value >=
                            (goal![cost.key] ?? 0),
                      ),
                )
                .toList()
          : legal.promotions;
      if (needDefence && promotions.isNotEmpty) {
        return _best<PromoteGuard>(
          promotions,
          (event) => state.guards[event.vertex]!.rank.strength.toDouble(),
          (event) => event.vertex,
        );
      }
      // Recruit while there is time to activate on a later turn.
      if (roundsUntilRaid > 1 &&
          legal.recruits.isNotEmpty &&
          ownGuards.length < 2 &&
          ownGuards.every((entry) => entry.value.active)) {
        return _best<RecruitGuard>(
          legal.recruits,
          (event) => _guardValue(state, event.vertex),
          (event) => event.vertex,
        );
      }
      if (needDefence && legal.fortifications.isNotEmpty) {
        return legal.fortifications.first;
      }
    }

    if (legal.guardMoves.isNotEmpty) {
      final move = _best<MoveGuard>(
        legal.guardMoves,
        (e) => _guardValue(state, e.to) - _guardValue(state, e.from),
        (e) => e.to,
      );
      if (_guardValue(state, move.to) > _guardValue(state, move.from) + 2) {
        return move;
      }
    }

    final capitals = legal.upgrades
        .where((e) => state.sites[e.vertex]!.structure == Structure.town)
        .toList();
    if (capitals.isNotEmpty) {
      return _best<UpgradeSite>(
        capitals,
        (e) => siteValue(state, e.vertex),
        (e) => e.vertex,
      );
    }

    // Legal village placement wins points and productive diversity now.
    if (legal.villages.isNotEmpty) {
      return _best<PlaceVillage>(
        legal.villages,
        (e) =>
            siteValue(state, e.vertex) +
            (_aggressive(state) ? _blockingValue(state, e.vertex) : 0),
        (e) => e.vertex,
      );
    }

    if (legal.upgrades.isNotEmpty) {
      return _best<UpgradeSite>(
        legal.upgrades,
        (e) => siteValue(state, e.vertex),
        (e) => e.vertex,
      );
    }

    final advanced = AiActionAdapter.advancedDecision(
      view,
      constructionGoal: goal,
      deferDefence: hard,
      deferExchange: hard,
    );
    if (advanced != null) return advanced;

    // A Town opens productive commodities; Commerce II improves all exchanges.
    final hasTown = state.sites.values.any(
      (s) => s.owner == state.active && s.structure != Structure.village,
    );
    if (hasTown && state.current.level(track) < 2) {
      for (final development in legal.developments) {
        if (development.track == track) return development;
      }
    }

    final card = AiCardStrategy.playCard(view, goal: goal);
    if (card != null) return card;

    final trade = hard
        ? _hardExchange(state, legal, goal!)
        : _exchange(state, legal);
    if (trade != null) return trade;

    // Roads are an investment only when they unlock useful, spaced sites.
    // Retain wood/brick if a village is already reachable but unaffordable.
    final availableSite = state.topology.vertices.any(
      (v) =>
          _open(state, v.id) &&
          v.edges.any((e) => state.roads[e] == state.active),
    );
    if (!availableSite &&
        legal.roads.isNotEmpty &&
        state.roads.values.where((p) => p == state.active).length <
            (hard ? MatchEngine.roadLimit : 12)) {
      final road = _best<PlaceRoad>(
        legal.roads,
        (e) => hard ? _hardRoadValue(state, e.edge) : _roadValue(state, e.edge),
        (e) => e.edge,
      );
      if ((hard
              ? _hardRoadValue(state, road.edge)
              : _roadValue(state, road.edge)) >=
          3) {
        return road;
      }
    }

    final proposal = AiCardStrategy.propose(
      view,
      goal: goal,
      cautious: hard,
      excluded: hard ? _recentRejectedOffers(state) : const [],
    );
    if (proposal != null) return proposal;
    return const EndTurn();
  }
}
