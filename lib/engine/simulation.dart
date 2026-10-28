import 'dart:math' as math;

import 'advanced.dart';
import 'balance.dart';
import 'board.dart';
import 'cards.dart';
import 'game.dart';
import 'match.dart';

/// A bounded, deterministic approximation of rational human play. No dice,
/// illegal actions, hidden information queries, or synthetic resources.
class BalanceBot {
  const BalanceBot(this.track, {this.trade = false, this.defend = false});

  final StrategyDeck track;
  final bool trade;
  final bool defend;
}

class BalanceMatch {
  BalanceMatch(
    this.state,
    this.bots,
    this.deficitSeats,
    this.unproductiveRounds,
    this.reactionOpportunities,
    this.reactionUses,
    this.cardValue,
    this.cardPlays,
    this.completedRounds,
  );

  final MatchState state;
  final List<BalanceBot> bots;
  final Set<int> deficitSeats;
  final int unproductiveRounds, reactionOpportunities, reactionUses;
  final Map<StrategyDeck, double> cardValue;
  final Map<StrategyDeck, int> cardPlays;
  final int completedRounds;
  int? get winner => MatchEngine.winner(state);
  bool get finished => winner != null;
  int get turns =>
      state.turnSerial + (state.phase == MatchPhase.actions ? 1 : 0);
}

class BalanceSimulation {
  static int _count(MatchState s, int player, Resource good) =>
      s.players[player].stores[good] ?? 0;

  static bool _open(MatchState s, int vertex) =>
      !s.sites.containsKey(vertex) &&
      !s.topology.neighbours(vertex).any(s.sites.containsKey);

  static double _siteValue(MatchState s, int vertex, BalanceBot bot) {
    var value = 0.0;
    final covered = <Resource>{};
    for (final entry in s.sites.entries) {
      if (entry.value.owner != s.active) continue;
      for (final tile in s.topology.vertices[entry.key].tiles) {
        final good = s.board.tiles[tile].land.produces;
        if (good != null) covered.add(good);
      }
    }
    for (final tile in s.topology.vertices[vertex].tiles) {
      final t = s.board.tiles[tile];
      final good = t.land.produces;
      if (good == null || t.productionNumber == null) continue;
      final pips = 6 - (7 - t.productionNumber!).abs();
      final base = good == Resource.wheat || good == Resource.ore ? 1.25 : 1.0;
      final diversity = covered.contains(good) ? 0.86 : 1.28;
      final preference = t.land == bot.track.sourceLand ? 1.12 : 1.0;
      value += pips * base * diversity * preference;
    }
    return value;
  }

  static int _bestVillage(MatchState s, BalanceBot bot) {
    final choices = MatchEngine.legalVertices(s);
    choices.sort((a, b) {
      final byValue = _siteValue(s, b, bot).compareTo(_siteValue(s, a, bot));
      return byValue != 0 ? byValue : a.compareTo(b);
    });
    return choices.first;
  }

  static int _bestRoad(MatchState s, BalanceBot bot) {
    final choices = MatchEngine.legalEdges(s);
    double value(int edge) {
      final e = s.topology.edges[edge];
      var result = -1.0;
      for (final vertex in [e.a, e.b]) {
        if (_open(s, vertex)) {
          result = math.max(result, _siteValue(s, vertex, bot));
        }
        for (final next in s.topology.neighbours(vertex)) {
          if (_open(s, next)) {
            result = math.max(result, _siteValue(s, next, bot) * 0.74);
          }
        }
      }
      return result;
    }

    choices.sort((a, b) {
      final order = value(b).compareTo(value(a));
      return order != 0 ? order : a.compareTo(b);
    });
    return choices.first;
  }

  static int _pickBanditTile(MatchState s) {
    var bestTile = -1;
    var best = double.negativeInfinity;
    for (var tile = 0; tile < s.board.tiles.length; tile++) {
      if (tile == s.banditTile) continue;
      var value = 0.0;
      final t = s.board.tiles[tile];
      for (final vertex in s.topology.tileVertices[tile]) {
        final site = s.sites[vertex];
        if (site == null) continue;
        final valuePerPip =
            (site.structure.points) *
            (1 + (MatchEngine.score(s, site.owner) / 15));
        value += site.owner == s.active ? -valuePerPip * 1.5 : valuePerPip;
      }
      if (t.productionNumber == null) value -= 12;
      if (value > best) {
        best = value;
        bestTile = tile;
      }
    }
    return bestTile;
  }

  static Map<Resource, int> _goal(MatchState s, BalanceBot bot) {
    final own = s.sites.entries
        .where((e) => e.value.owner == s.active)
        .toList();
    final towns = own
        .where((e) => e.value.structure != Structure.village)
        .toList();
    if (towns.isEmpty) return MatchEngine.townCost;
    if (own.length < 4 &&
        s.roads.values.where((p) => p == s.active).length >= 2) {
      final possible = s.topology.vertices.any(
        (v) => _open(s, v.id) && v.edges.any((e) => s.roads[e] == s.active),
      );
      if (possible) return MatchEngine.villageCost;
    }
    if (s.current.level(bot.track) < 2) {
      return MatchEngine.developmentCost(
        s,
        bot.track,
        s.current.level(bot.track) + 1,
      );
    }
    if (own.any((e) => e.value.structure == Structure.town) &&
        MatchEngine.affordable(s, MatchEngine.capitalCost)) {
      return MatchEngine.capitalCost;
    }
    if (own.length < 5) return MatchEngine.villageCost;
    return MatchEngine.townCost;
  }

  static BankExchange? _bankTrade(MatchState s, BalanceBot bot) {
    final goal = _goal(s, bot);
    final rate = MatchEngine.tradeRate(s, s.active);
    final wanted = Resource.values
        .where(
          (r) =>
              (goal[r] ?? 0) > _count(s, s.active, r) &&
              (s.bank[r] ?? 0) >=
                  (s.current.level(StrategyDeck.commerce) >= 5
                      ? s.balance.bazaarGoods
                      : s.current.level(StrategyDeck.commerce) >= 3 &&
                            r == Resource.cloth
                      ? 2
                      : 1),
        )
        .toList();
    if (wanted.isEmpty) return null;
    wanted.sort(
      (a, b) => (goal[b]! - _count(s, s.active, b)).compareTo(
        goal[a]! - _count(s, s.active, a),
      ),
    );
    final give = Resource.values
        .where(
          (r) =>
              r != wanted.first &&
              _count(s, s.active, r) >= rate &&
              (_count(s, s.active, r) - rate >= (goal[r] ?? 0) ||
                  _count(s, s.active, r) >= rate + 2),
        )
        .toList();
    if (give.isEmpty) return null;
    give.sort(
      (a, b) => _count(s, s.active, b).compareTo(_count(s, s.active, a)),
    );
    return BankExchange(give.first, wanted.first);
  }

  static ProposeTrade? _offer(MatchState s, BalanceBot bot) {
    if (!bot.trade || s.offers.any((o) => o.proposer == s.active)) return null;
    final goal = _goal(s, bot);
    final wanted = Resource.values
        .where((r) => _count(s, s.active, r) < (goal[r] ?? 0))
        .toList();
    final spare = Resource.values
        .where((r) => _count(s, s.active, r) > (goal[r] ?? 0) + 1)
        .toList();
    if (wanted.isEmpty || spare.isEmpty) return null;
    final target =
        (s.active + 1 + s.round % (s.players.length - 1)) % s.players.length;
    if (target == s.active) return null;
    return ProposeTrade(target, spare.first, 1, wanted.first, 1);
  }

  static PlayStrategyCard? _card(MatchState s, BalanceBot bot) {
    final goal = _goal(s, bot);
    for (var i = 0; i < s.current.cards.length; i++) {
      final options = MatchEngine.legalCardPlays(s, i);
      if (options.isEmpty) continue;
      final power = s.current.cards[i].definition.power;
      if (power == CardPower.moveBandit && s.round < 5) continue;
      if (power == CardPower.exhaust && !bot.defend) continue;
      options.sort((a, b) {
        double quality(PlayStrategyCard x) {
          if (x.receive != null) {
            return ((goal[x.receive] ?? 0) - _count(s, s.active, x.receive!)) *
                    4 +
                (x.receive!.index < 5 ? 2 : 1);
          }
          if (x.target != null) return MatchEngine.score(s, x.target!) * 2;
          if (x.vertex != null) {
            if (power == CardPower.freeRoad) {
              final edge = s.topology.edges[x.vertex!];
              return [
                _siteValue(s, edge.a, bot),
                _siteValue(s, edge.b, bot),
              ].reduce(math.max);
            }
            return x.vertex!.toDouble() * -0.001;
          }
          if (x.tile != null) return x.tile == _pickBanditTile(s) ? 30 : 0;
          return 1;
        }

        final diff = quality(b).compareTo(quality(a));
        return diff != 0 ? diff : a.handIndex.compareTo(b.handIndex);
      });
      return options.first;
    }
    return null;
  }

  static double _impact(MatchState before, MatchState after, int seat) {
    double value(MatchState s) {
      final goods = s.players[seat].stores.entries.fold<double>(
        0,
        (v, e) => v + e.value * (e.key.index >= 5 ? 1.5 : 1),
      );
      final roads = s.roads.values.where((p) => p == seat).length;
      final forts = s.fortified.where((v) => s.sites[v]?.owner == seat).length;
      final military = s.knights.values
          .where((k) => k.owner == seat && k.active)
          .fold<int>(0, (v, k) => v + k.rank.strength);
      return goods +
          2 * roads +
          2.5 * forts +
          military +
          5 * MatchEngine.score(s, seat);
    }

    return value(after) - value(before);
  }

  static BalanceMatch run({
    required int seed,
    MatchBalance balance = MatchBalance.baseline,
    int seats = 3,
    int maxRounds = 65,
  }) {
    if (seats < 3 || seats > 4 || maxRounds < 1) {
      throw ArgumentError('3–4 seats and positive round cap required.');
    }
    // Rotate tracks independently of trading and defence temperaments,
    // so track win share is not confounded by a single behaviour policy.
    final bots = List.generate(seats, (i) {
      final track = StrategyDeck.values[(i + seed % 3) % 3];
      final temperament = (i + seed ~/ 3) % 3;
      return BalanceBot(
        track,
        trade: temperament != 0,
        defend: temperament != 1,
      );
    });
    var s = MatchEngine.newGame(
      List.generate(seats, (i) => 'Bot-$i'),
      seed,
      boardSeed: seed * 7 + 11,
      balance: balance,
    );
    final deficit = <int>{};
    var unproductive = 0, opportunities = 0, uses = 0, completedRounds = 0;
    var productive = false;
    final values = {for (final track in StrategyDeck.values) track: 0.0};
    final plays = {for (final track in StrategyDeck.values) track: 0};
    MatchState? cardBefore;
    StrategyDeck? pendingTrack;
    int? cardActor;

    void observe(MatchState old, MatchState next, MatchEvent event) {
      if (event is RespondTactical) {
        opportunities++;
        if (event.choice != TacticalChoice.pass) uses++;
      }
      if (event is PlayStrategyCard) {
        cardBefore = old;
        pendingTrack = old.current.cards[event.handIndex].track;
        cardActor = old.active;
        plays[pendingTrack!] = plays[pendingTrack!]! + 1;
        productive = true;
      }
      if (pendingTrack != null && next.tactical == null) {
        values[pendingTrack!] =
            values[pendingTrack!]! + _impact(cardBefore!, next, cardActor!);
        pendingTrack = null;
        cardBefore = null;
      }
      if (event is PlaceRoad ||
          event is PlaceVillage ||
          event is UpgradeSite ||
          event is DevelopTown ||
          event is RecruitKnight ||
          event is ActivateKnight ||
          event is FortifyTown ||
          event is BankExchange ||
          event is RespondTrade && event.accept) {
        productive = true;
      }
      if (event is EndTurn && next.active == 0) {
        completedRounds++;
        if (!productive) unproductive++;
        productive = false;
      }
      final lead = List.generate(
        next.players.length,
        (p) => MatchEngine.score(next, p),
      ).reduce(math.max);
      for (var i = 0; i < next.players.length; i++) {
        if (lead >= 8 && lead - MatchEngine.score(next, i) >= 3) deficit.add(i);
      }
    }

    void dispatch(MatchEvent event) {
      final old = s;
      s = MatchEngine.apply(s, event);
      observe(old, s, event);
    }

    while (s.phase != MatchPhase.finished && s.round <= maxRounds) {
      if (s.tactical != null) {
        final w = s.tactical!, bot = bots[w.responder];
        var choice = TacticalChoice.pass;
        int? counter;
        Resource? aid;
        if (w.kind == TacticalKind.bandit &&
            bot.defend &&
            MatchEngine.canIntercept(s, w.responder)) {
          choice = TacticalChoice.intercept;
        } else if (w.kind == TacticalKind.governance) {
          final counters = MatchEngine.counterCards(s, w.responder, w.card!);
          if (counters.isNotEmpty) {
            choice = TacticalChoice.counter;
            counter = counters.first;
          }
        } else if (w.kind == TacticalKind.invasion &&
            bot.defend &&
            MatchEngine.defenceStrength(s) + s.invasionAid <
                MatchEngine.invasionStrength(s)) {
          final gap =
              MatchEngine.invasionStrength(s) -
              MatchEngine.defenceStrength(s) -
              s.invasionAid;
          if (gap <= 2 && _count(s, w.responder, Resource.ore) > 0) {
            choice = TacticalChoice.aid;
            aid = Resource.ore;
          } else if (gap == 1 && _count(s, w.responder, Resource.wheat) > 0) {
            choice = TacticalChoice.aid;
            aid = Resource.wheat;
          }
        }
        dispatch(
          RespondTactical(
            w.id,
            w.responder,
            choice,
            cardIndex: counter,
            good: aid,
          ),
        );
        continue;
      }
      if (s.phase == MatchPhase.setupVillage) {
        dispatch(PlaceVillage(_bestVillage(s, bots[s.active])));
        continue;
      }
      if (s.phase == MatchPhase.setupRoad) {
        dispatch(PlaceRoad(_bestRoad(s, bots[s.active])));
        continue;
      }
      if (s.phase == MatchPhase.invasion) {
        dispatch(const ResolveInvasion());
        continue;
      }
      if (s.phase == MatchPhase.roll) {
        dispatch(
          RollDice(
            MatchEngine.expectedDice(s).$1,
            MatchEngine.expectedDice(s).$2,
          ),
        );
        continue;
      }
      if (s.phase == MatchPhase.bandit) {
        final tile = _pickBanditTile(s);
        final victims = MatchEngine.banditVictims(s, tile);
        victims.sort(
          (a, b) => MatchEngine.score(s, b).compareTo(MatchEngine.score(s, a)),
        );
        dispatch(
          MoveBandit(tile, victim: victims.isEmpty ? null : victims.first),
        );
        continue;
      }
      if (s.phase != MatchPhase.actions) {
        throw StateError('Unexpected simulation phase');
      }
      final bot = bots[s.active];
      var roads = 0, banks = 0, cards = 0, offers = 0, military = 0;
      for (
        var action = 0;
        action < 14 && s.phase == MatchPhase.actions;
        action++
      ) {
        final own = s.sites.entries
            .where((e) => e.value.owner == s.active)
            .toList();
        final town = own
            .where((e) => e.value.structure == Structure.town)
            .toList();
        final legalUpgrades = MatchEngine.legalUpgrades(s);
        final capital = legalUpgrades
            .where((v) => s.sites[v]!.structure == Structure.town)
            .toList();
        if (capital.isNotEmpty) {
          dispatch(UpgradeSite(capital.first));
          continue;
        }
        final villages = MatchEngine.legalVertices(s);
        if (villages.isNotEmpty && own.length < 7) {
          dispatch(PlaceVillage(_bestVillage(s, bot)));
          continue;
        }
        if (legalUpgrades.isNotEmpty &&
            (town.isEmpty || own.length >= 3 || s.round % 3 != 0)) {
          dispatch(UpgradeSite(legalUpgrades.first));
          continue;
        }
        if (town.isNotEmpty &&
            MatchEngine.canDevelop(s, bot.track) &&
            (s.current.level(bot.track) < 2 ||
                (s.current.level(bot.track) < 4 && s.round % 2 == 0))) {
          dispatch(DevelopTown(bot.track));
          continue;
        }
        if (cards < 2) {
          final card = _card(s, bot);
          if (card != null) {
            cards++;
            dispatch(card);
            if (s.tactical != null) break;
            continue;
          }
        }
        if (bot.defend && military < 2) {
          final inactive =
              s.knights.keys
                  .where((v) => MatchEngine.legalActivate(s, v))
                  .toList()
                ..sort();
          if (inactive.isNotEmpty) {
            military++;
            dispatch(ActivateKnight(inactive.first));
            continue;
          }
          final positions = List.generate(
            s.topology.vertices.length,
            (i) => i,
          ).where((v) => MatchEngine.legalRecruit(s, v)).toList();
          if (positions.isNotEmpty &&
              (s.round % 3 == 0 || s.reaverPressure >= 2)) {
            military++;
            dispatch(RecruitKnight(positions.first));
            continue;
          }
        }
        if (roads < 2 &&
            own.length < 7 &&
            s.roads.values.where((p) => p == s.active).length < 12 &&
            MatchEngine.legalEdges(s).isNotEmpty) {
          roads++;
          dispatch(PlaceRoad(_bestRoad(s, bot)));
          continue;
        }
        if (banks < 2) {
          final trade = _bankTrade(s, bot);
          if (trade != null) {
            banks++;
            dispatch(trade);
            continue;
          }
        }
        if (offers < 1) {
          final offer = _offer(s, bot);
          offers++;
          if (offer != null) {
            dispatch(offer);
            continue;
          }
        }
        if (legalUpgrades.isNotEmpty) {
          dispatch(UpgradeSite(legalUpgrades.first));
          continue;
        }
        break;
      }
      if (s.tactical != null || s.phase == MatchPhase.finished) continue;
      // Offers are answered on the recipient's own action turn.
      final incoming = s.offers.where((o) => o.target == s.active).toList();
      for (final offer in incoming) {
        final ownWant = _goal(s, bot)[offer.give] ?? 0;
        final accept =
            _count(s, s.active, offer.want) >= offer.wantCount &&
            (_count(s, s.active, offer.want) > offer.wantCount ||
                ownWant > _count(s, s.active, offer.give));
        dispatch(RespondTrade(s.active, accept, offerId: offer.id));
      }
      if (s.phase == MatchPhase.actions) dispatch(const EndTurn());
    }
    return BalanceMatch(
      s,
      bots,
      deficit,
      unproductive,
      opportunities,
      uses,
      values,
      plays,
      completedRounds,
    );
  }
}
