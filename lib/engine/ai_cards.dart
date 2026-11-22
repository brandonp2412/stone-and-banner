import 'ai.dart';
import 'board.dart';
import 'cards.dart';
import 'game.dart';
import 'match.dart';

/// Seat-scoped, deterministic choices for cards, public offers and tactical
/// windows. This policy accepts only [AiTurnView], never the canonical match,
/// rival inventories, hidden draw piles or future random outcomes.
abstract final class AiCardStrategy {
  static Map<Resource, int> _goal(AiTurnView view) {
    final sites = view.strategy.ownSites.values;
    if (sites.contains(Structure.village)) return MatchEngine.townCost;
    if (sites.contains(Structure.town)) return MatchEngine.capitalCost;
    return MatchEngine.villageCost;
  }

  static double _utility(Map<Resource, int> stores, Map<Resource, int> goal) {
    var total = 0.0;
    for (final good in Resource.values) {
      final count = stores[good] ?? 0;
      final needed = goal[good] ?? 0;
      final useful = count < needed ? count : needed;
      total += useful * 8 + (count - useful) * 0.45;
    }
    return total;
  }

  static double _tradeGain(
    AiTurnView view,
    Resource give,
    int giveCount,
    Resource receive,
    int receiveCount,
  ) {
    final before = Map<Resource, int>.of(view.ownGoods);
    if ((before[give] ?? 0) < giveCount) return -1000;
    final after = Map<Resource, int>.of(before)
      ..[give] = before[give]! - giveCount
      ..[receive] = (before[receive] ?? 0) + receiveCount;
    final goal = _goal(view);
    return _utility(after, goal) - _utility(before, goal);
  }

  static double _bundleGain(
    AiTurnView view,
    Map<Resource, int> gives,
    Map<Resource, int> wants,
  ) {
    if (!canPayTrade(view.ownGoods, gives)) return -1000;
    final after = Map<Resource, int>.of(view.ownGoods);
    for (final e in gives.entries) {
      after[e.key] = (after[e.key] ?? 0) - e.value;
    }
    for (final e in wants.entries) {
      after[e.key] = (after[e.key] ?? 0) + e.value;
    }
    final goal = _goal(view);
    return _utility(after, goal) - _utility(view.ownGoods, goal);
  }

  static MatchEvent? tactical(AiTurnView view) {
    final responses = view.legalActions.whereType<RespondTactical>().toList();
    if (responses.isEmpty) return null;
    final pass = responses.firstWhere((e) => e.choice == TacticalChoice.pass);
    final counters = responses.where((e) => e.choice == TacticalChoice.counter);
    if (counters.isNotEmpty) return counters.first;
    final intercept = responses.where(
      (e) => e.choice == TacticalChoice.intercept,
    );
    if (intercept.isNotEmpty &&
        view.ownGoods.values.fold<int>(0, (a, b) => a + b) > 0) {
      return intercept.first;
    }
    final gap =
        view.strategy.invasionThreat -
        view.strategy.sharedDefence -
        view.strategy.invasionAid;
    final availableAid = responses
        .where((e) => e.choice == TacticalChoice.aid)
        .toList();
    // Count our own strongest *legal* pledge and only an upper bound for
    // later responders. Their hidden inventory is never inspected.
    final ownMax = availableAid.any((e) => e.good == Resource.ore) ? 2 : 1;
    if (gap <= 0 ||
        availableAid.isEmpty ||
        gap > ownMax + view.strategy.aidRespondersRemaining * 2) {
      return pass;
    }
    if (gap == 1) {
      for (final aid in availableAid) {
        if (aid.good == Resource.wheat) return aid;
      }
    }
    for (final aid in availableAid) {
      if (aid.good == Resource.ore) return aid;
    }
    return availableAid.first;
  }

  /// Responds to visible outstanding offers before any optional turn spending.
  /// Counters only original offers, never a counter to a counter.
  static MatchEvent? incomingOffer(AiTurnView view) {
    if (view.phase != MatchPhase.actions) return null;
    final offers =
        view.publicOffers.where((o) => o.canRespond(view.seat)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    if (offers.isEmpty) return null;
    final offer = offers.first;
    final accepts = view.legalActions.whereType<RespondTrade>().where(
      (e) => e.offerId == offer.id && e.accept,
    );
    // A clear surplus of goods is a windfall even when today's build goal
    // values the outgoing single good more highly than the incoming bundle.
    final surplus =
        offer.gives.values.fold<int>(0, (a, b) => a + b) -
        offer.wants.values.fold<int>(0, (a, b) => a + b);
    if (accepts.isNotEmpty &&
        (_bundleGain(view, offer.wants, offer.gives) > 0.5 || surplus >= 2)) {
      return accepts.first;
    }
    if (!offer.isCounter) {
      final counters = view.legalActions
          .whereType<ProposeTrade>()
          .where((e) => e.counterOf == offer.id)
          .toList();
      counters.sort((a, b) {
        final quality = _bundleGain(
          view,
          b.gives,
          b.wants,
        ).compareTo(_bundleGain(view, a.gives, a.wants));
        return quality != 0 ? quality : a.give.index.compareTo(b.give.index);
      });
      if (counters.isNotEmpty &&
          _bundleGain(view, counters.first.gives, counters.first.wants) > 0.5) {
        return counters.first;
      }
    }
    for (final action in view.legalActions.whereType<RespondTrade>()) {
      if (action.offerId == offer.id && !action.accept) return action;
    }
    return null;
  }

  static double _cardValue(AiTurnView view, PlayStrategyCard play) {
    final definition = view.ownCards[play.handIndex].definition;
    final goal = _goal(view);
    final bank = view.strategy.bankStock;
    double receipt(Resource good, int count) {
      if ((bank[good] ?? 0) < count) return -100;
      final have = view.ownGoods[good] ?? 0;
      final needed = goal[good] ?? 0;
      final useful = (needed - have).clamp(0, count);
      return useful * 8.0 + (count - useful) * 0.7;
    }

    final danger =
        view.strategy.pressure >= 2 &&
        view.strategy.sharedDefence < view.strategy.invasionThreat;
    switch (definition.power) {
      case CardPower.fixedGoods:
        return definition.goods.entries.fold<double>(
          0,
          (value, e) => value + receipt(e.key, e.value),
        );
      case CardPower.chooseBasic:
      case CardPower.chooseCommodity:
        return receipt(play.receive!, definition.amount);
      case CardPower.freeRoad:
        return view.strategy.ownSites.isEmpty ? 4 : 7;
      case CardPower.freeFort:
        return danger ? 15 : 3;
      case CardPower.swap:
      case CardPower.portSwap:
      case CardPower.leverageSwap:
        return _tradeGain(
          view,
          play.give!,
          definition.power == CardPower.leverageSwap ? 2 : 1,
          play.receive!,
          definition.power == CardPower.portSwap ? 2 : 1,
        );
      case CardPower.activate:
        return danger ? 14 : 4;
      case CardPower.promote:
        return danger ? 12 : 3;
      case CardPower.exhaust:
        final knight = view.strategy.publicKnights[play.vertex];
        return knight != null && knight.owner != view.seat
            ? knight.rank.strength * (danger ? 2.0 : 1.0) +
                  view.publicScores[knight.owner] * 0.8
            : -100;
      case CardPower.moveBandit:
        return 1; // Cannot infer a hidden victim's inventory.
      case CardPower.massRaid:
        return 18; // One stolen resource from each rival.
      case CardPower.massExhaust:
        return danger ? 14 : 10;
      case CardPower.seizeGood:
        return -100; // Never peek into an opponent's hand to find a target.
    }
  }

  static MatchEvent? playCard(AiTurnView view) {
    if (view.phase != MatchPhase.actions || view.actionsSinceRoll >= 7) {
      return null;
    }
    final plays = view.legalActions.whereType<PlayStrategyCard>().toList();
    plays.sort((a, b) {
      final score = _cardValue(view, b).compareTo(_cardValue(view, a));
      if (score != 0) return score;
      final hand = a.handIndex.compareTo(b.handIndex);
      if (hand != 0) return hand;
      return a.toJson().toString().compareTo(b.toJson().toString());
    });
    if (plays.isNotEmpty && _cardValue(view, plays.first) > 1.5) {
      return plays.first;
    }
    // At the hand limit, free a slot for the next deterministic event draw.
    if (view.ownCards.length >= StrategyCards.handLimit) {
      final discards = view.legalActions.whereType<DiscardStrategyCard>();
      if (discards.isNotEmpty) {
        final playable = plays.map((a) => a.handIndex).toSet();
        for (final discard in discards) {
          if (!playable.contains(discard.handIndex)) return discard;
        }
        return discards.last;
      }
    }
    return null;
  }

  /// A bounded public bundle offer. The rival may decline; never assume their
  /// private stores. Keep one outstanding offer per proposer as per reducer.
  /// A conservative estimate of whether the *recipient* benefits. Only
  /// publicly visible build requirements and production are considered;
  /// another player's hidden hand is never inspected.
  static double _recipientAppeal(AiTurnView view, ProposeTrade offer) {
    final goal = view.publicGoals[offer.target];
    final production = view.publicProduction[offer.target];
    // Asking for multiple copies of one good is particularly likely to fail:
    // even a producing player may not have that much in hand.
    if (offer.wants.values.any((amount) => amount > 1)) return -1000;

    double value(Resource good) {
      final usefulForBuild = (goal[good] ?? 0) > 0;
      final produces = production[good] ?? false;
      // Roads are useful even when the next settlement upgrade needs ore.
      final usefulForExpansion = good == Resource.wood || good == Resource.brick
          ? 0.7
          : 0.0;
      return (usefulForBuild ? 2.4 : 0.6) +
          (produces ? 0 : 0.85) +
          usefulForExpansion;
    }

    var received = 0.0;
    for (final entry in offer.gives.entries) {
      received += value(entry.key) * entry.value;
    }
    var paid = 0.0;
    for (final entry in offer.wants.entries) {
      paid += value(entry.key) * entry.value;
    }
    return received - paid;
  }

  static MatchEvent? propose(AiTurnView view) {
    if (view.phase != MatchPhase.actions ||
        view.actionsSinceRoll > 3 ||
        view.publicOffers.any((o) => o.proposer == view.seat)) {
      return null;
    }
    final candidates = view.legalActions
        .whereType<ProposeTrade>()
        .where(
          (offer) =>
              offer.counterOf == null &&
              _bundleGain(view, offer.gives, offer.wants) > 0.5 &&
              _recipientAppeal(view, offer) > 0.75,
        )
        .toList();
    if (candidates.isEmpty) return null; // Better no offer than a bad offer.

    // Rank mutually useful exchanges, rather than maximizing only our gain.
    // Reward modest generosity: a 2-for-1 of useful goods is more likely to
    // be accepted than a 1-for-1 that only benefits the proposer.
    double value(ProposeTrade offer) {
      final count =
          offer.gives.values.fold<int>(0, (a, b) => a + b) +
          offer.wants.values.fold<int>(0, (a, b) => a + b);
      return _bundleGain(view, offer.gives, offer.wants) / count +
          1.25 * _recipientAppeal(view, offer);
    }

    // Within comparably fair offers, avoid feeding the current leader.
    final next = List.generate(view.publicScores.length, (i) => i)
        .where((seat) => seat != view.seat)
        .reduce((a, b) => view.publicScores[a] <= view.publicScores[b] ? a : b);
    candidates.sort((a, b) {
      final score = value(b).compareTo(value(a));
      if (score != 0) return score;
      final target = (a.target == next ? 0 : 1).compareTo(
        b.target == next ? 0 : 1,
      );
      if (target != 0) return target;
      final give = a.give.index.compareTo(b.give.index);
      return give != 0 ? give : a.want.index.compareTo(b.want.index);
    });
    return candidates.first;
  }
}
