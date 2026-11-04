import 'dart:math' as math;

import 'ai.dart';
import 'board.dart';
import 'cards.dart';
import 'game.dart';
import 'match.dart';

/// Exposes only actions validated by the pure match engine. The bot never
/// invents placements, exchanges or dice outcomes.
class AiLegalActions {
  AiLegalActions(MatchState state)
    : _options = AiActionAdapter.observe(
        state,
        state.tactical?.responder ?? state.active,
      ).legalActions;

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
  const HeuristicAi({this.track = StrategyDeck.commerce});

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
    return sorted.first;
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
        // Do not route through a rival settlement.
        if (state.sites[vertex]?.owner != null &&
            state.sites[vertex]!.owner != state.active) {
          continue;
        }
        if (_open(state, next) && !accessible.contains(next)) {
          best = math.max(best, siteValue(state, next) * 0.72);
        }
      }
    }
    return best;
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
        var value = 0.0;
        for (final vertex in state.topology.tileVertices[event.tile]) {
          final site = state.sites[vertex];
          if (site == null) continue;
          final weight =
              (site.structure.points + 1) * (_pips[tile.productionNumber] ?? 0);
          value += site.owner == state.active
              ? -weight * 2.2
              : weight * (1 + MatchEngine.score(state, site.owner) / 15);
        }
        return value;
      }, (event) => event.tile * 4 + (event.victim ?? 0));

  MatchEvent _tactical(MatchState state, AiLegalActions legal) {
    final window = state.tactical!;
    final options = legal.tactical;
    if (window.kind == TacticalKind.bandit ||
        window.kind == TacticalKind.governance) {
      for (final action in options) {
        if (action.choice == TacticalChoice.intercept ||
            action.choice == TacticalChoice.counter) {
          return action;
        }
      }
    }
    if (window.kind == TacticalKind.invasion) {
      final gap =
          MatchEngine.invasionStrength(state) -
          MatchEngine.defenceStrength(state) -
          state.invasionAid;
      if (gap > 0 && gap <= 2) {
        for (final action in options) {
          if (action.choice == TacticalChoice.aid &&
              action.good == Resource.ore) {
            return action;
          }
        }
        if (gap == 1) {
          for (final action in options) {
            if (action.choice == TacticalChoice.aid &&
                action.good == Resource.wheat) {
              return action;
            }
          }
        }
      }
    }
    return options.first; // Adapter enumerates a legal Pass first.
  }

  MatchEvent? choose(MatchState state) {
    if (state.phase == MatchPhase.finished) return null;
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

  MatchEvent _action(MatchState state, AiLegalActions legal) {
    // Resolve incoming offers using our own inventory and near-term goal.
    final incoming = state.offers.where((o) => o.target == state.active);
    if (incoming.isNotEmpty) {
      final offer = incoming.first;
      final goal = _goal(state);
      final accept =
          _have(state, offer.want) >= offer.wantCount &&
          _have(state, offer.give) < (goal[offer.give] ?? 0) &&
          _have(state, offer.want) - offer.wantCount >= (goal[offer.want] ?? 0);
      return RespondTrade(state.active, accept, offerId: offer.id);
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

    // Legal settlement placement wins points and productive diversity now.
    if (legal.villages.isNotEmpty) {
      return _best<PlaceVillage>(
        legal.villages,
        (e) => siteValue(state, e.vertex),
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

    // A Town opens productive commodities; Commerce II improves all exchanges.
    final hasTown = state.sites.values.any(
      (s) => s.owner == state.active && s.structure != Structure.village,
    );
    if (hasTown && state.current.level(track) < 2) {
      for (final development in legal.developments) {
        if (development.track == track) return development;
      }
    }

    final goal = _goal(state);
    for (final card in legal.cards) {
      final definition = state.current.cards[card.handIndex].definition;
      // Play useful production cards but avoid spending tactical cards blindly.
      if (definition.power == CardPower.fixedGoods ||
          definition.power == CardPower.chooseBasic ||
          definition.power == CardPower.chooseCommodity ||
          definition.power == CardPower.freeRoad) {
        if (card.receive != null &&
            (goal[card.receive] ?? 0) <= _have(state, card.receive!)) {
          continue;
        }
        return card;
      }
    }

    final trade = _exchange(state, legal);
    if (trade != null) return trade;

    // Roads are an investment only when they unlock useful, spaced sites.
    // Retain wood/brick if a settlement is already reachable but unaffordable.
    final availableSite = state.topology.vertices.any(
      (v) =>
          _open(state, v.id) &&
          v.edges.any((e) => state.roads[e] == state.active),
    );
    if (!availableSite &&
        legal.roads.isNotEmpty &&
        state.roads.values.where((p) => p == state.active).length < 12) {
      final road = _best<PlaceRoad>(
        legal.roads,
        (e) => _roadValue(state, e.edge),
        (e) => e.edge,
      );
      if (_roadValue(state, road.edge) >= 3) return road;
    }

    // Defensive spending is secondary to points and infrastructure.
    if (state.reaverPressure >= 2) {
      final inactive =
          state.knights.keys
              .where((v) => MatchEngine.legalActivate(state, v))
              .toList()
            ..sort();
      if (inactive.isNotEmpty && _have(state, Resource.wheat) > 1) {
        return ActivateKnight(inactive.first);
      }
    }
    return const EndTurn();
  }
}
