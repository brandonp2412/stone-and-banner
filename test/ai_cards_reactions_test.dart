import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/ai_cards.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

MatchState fixture({int seed = 5}) => MatchEngine.newGame([
  'Ada',
  'Ben',
  'Cora',
], seed).copyWith(phase: MatchPhase.actions);

MatchState stock(MatchState state, int seat, Map<Resource, int> stores) {
  final players = state.players.toList();
  final bank = Map<Resource, int>.of(state.bank);
  final previous = players[seat].stores;
  for (final resource in Resource.values) {
    bank[resource] =
        bank[resource]! + (previous[resource] ?? 0) - (stores[resource] ?? 0);
    expect(bank[resource], greaterThanOrEqualTo(0));
  }
  players[seat] = players[seat].copyWith(stores: stores);
  return state.copyWith(players: players, bank: bank);
}

MatchState cards(MatchState state, int seat, List<HeldCard> hand) {
  final players = state.players.toList();
  players[seat] = players[seat].copyWith(cards: hand);
  return state.copyWith(players: players);
}

HeldCard held(StrategyDeck deck, String id) {
  final index = StrategyCards.deck(deck).indexWhere((c) => c.id == id);
  expect(index, greaterThanOrEqualTo(0));
  return HeldCard(deck, index);
}

/// The policy uses only a rival's publicly visible productive sites.
MatchState showProduction(
  MatchState state,
  int seat,
  Iterable<Resource> goods,
) {
  final sites = Map<int, Site>.of(state.sites);
  for (final good in goods) {
    final vertex = state.topology.vertices.firstWhere(
      (vertex) =>
          !sites.containsKey(vertex.id) &&
          vertex.tiles.any(
            (tile) => state.board.tiles[tile].land.produces == good,
          ),
    );
    sites[vertex.id] = Site(seat, Structure.village);
  }
  return state.copyWith(sites: sites);
}

void conserve(MatchState state) {
  for (final resource in Resource.values) {
    final total =
        (state.bank[resource] ?? 0) +
        state.players.fold<int>(0, (n, p) => n + (p.stores[resource] ?? 0));
    expect(total, MatchEngine.bankSupply, reason: resource.name);
  }
}

void main() {
  test('all 54 cards are present; each index can safely play or pass', () {
    expect(StrategyCards.definitions.length, 28);
    expect(StrategyDeck.values.length, 3);
    expect(
      StrategyDeck.values.fold<int>(
        0,
        (sum, deck) => sum + StrategyCards.deck(deck).length,
      ),
      54,
    );
    for (final deck in StrategyDeck.values) {
      expect(StrategyCards.deck(deck), hasLength(18));
      for (var index = 0; index < 18; index++) {
        var s = cards(fixture(seed: 500 + deck.index * 18 + index), 0, [
          HeldCard(deck, index),
        ]);
        s = stock(s, 0, {for (final r in Resource.values) r: 2});
        final view = AiActionAdapter.observe(s, 0);
        expect(
          view.legalActions.whereType<DiscardStrategyCard>(),
          hasLength(1),
        );
        final play = AiCardStrategy.playCard(view);
        if (play != null) {
          expect(
            view.legalActions.map((e) => e.toJson().toString()),
            contains(play.toJson().toString()),
          );
          final after = AiActionAdapter.applySelected(s, view, play);
          expect(after.events, hasLength(1));
          conserve(after);
        }
      }
    }
  });

  test('Innovation, Commerce and Governance choose useful legal plays', () {
    final selections = <(HeldCard, Map<Resource, int>, Resource?, bool)>[
      (
        held(StrategyDeck.innovation, 'bountiful-harvest'),
        {Resource.ore: 3},
        Resource.wheat,
        true,
      ),
      (
        held(StrategyDeck.commerce, 'port-exchange'),
        {Resource.wheat: 2, Resource.cloth: 1},
        Resource.ore,
        true,
      ),
      (held(StrategyDeck.governance, 'founding-charter'), {}, null, false),
    ];
    for (final (card, goods, wanted, hasVillage) in selections) {
      final base = hasVillage
          ? fixture().copyWith(sites: {0: const Site(0, Structure.village)})
          : fixture();
      final s = cards(stock(base, 0, goods), 0, [card]);
      final view = AiActionAdapter.observe(s, 0);
      final move = AiCardStrategy.playCard(view);
      expect(move, isA<PlayStrategyCard>(), reason: card.definition.id);
      if (wanted != null) {
        expect((move as PlayStrategyCard).receive, wanted);
      }
      final after = AiActionAdapter.applySelected(s, view, move!);
      expect(after.current.cards, isEmpty);
      conserve(after);
    }
  });

  test(
    'Bandit intercept or safe pass, no stale response/indefinite window',
    () {
      var s = fixture().copyWith(
        phase: MatchPhase.bandit,
        knights: {2: const KnightPiece(1, KnightRank.sentinel, true, -1)},
        tactical: TacticalWindow(7, TacticalKind.bandit, 0, [
          1,
        ], bandit: const MoveBandit(1, victim: 1)),
      );
      s = stock(s, 1, {Resource.ore: 1});
      final view = AiActionAdapter.observe(s, 1);
      final action = AiCardStrategy.tactical(view);
      expect(action, isA<RespondTactical>());
      expect((action as RespondTactical).choice, TacticalChoice.intercept);
      final after = AiActionAdapter.applySelected(s, view, action);
      expect(after.tactical, isNull);
      expect(after.knights[2]!.active, isFalse);
      expect(after.players[1].stores[Resource.ore], 1);
      conserve(after);
      expect(() => MatchEngine.apply(after, action), throwsStateError);

      final noGoods = stock(s, 1, {});
      final safe = AiCardStrategy.tactical(
        AiActionAdapter.observe(noGoods, 1),
      )!;
      expect((safe as RespondTactical).choice, TacticalChoice.pass);
      expect(MatchEngine.apply(noGoods, safe).tactical, isNull);
      final timed = MatchEngine.apply(noGoods, const TimeoutTactical(7, 1));
      expect(timed.tactical, isNull);
    },
  );

  test('Governance counter consumes two cards once and closes the window', () {
    var s = cards(fixture(), 0, [held(StrategyDeck.governance, 'supply-raid')]);
    s = cards(s, 1, [held(StrategyDeck.governance, 'boundary-dispute')]);
    s = stock(s, 1, {Resource.wheat: 2});
    s = s.copyWith(
      tactical: TacticalWindow(8, TacticalKind.governance, 0, [
        1,
      ], card: const PlayStrategyCard(0, target: 1, receive: Resource.wheat)),
    );
    final view = AiActionAdapter.observe(s, 1);
    final chosen = AiCardStrategy.tactical(view)!;
    expect((chosen as RespondTactical).choice, TacticalChoice.counter);
    final after = AiActionAdapter.applySelected(s, view, chosen);
    expect(after.tactical, isNull);
    expect(after.players[0].cards, isEmpty);
    expect(after.players[1].cards, isEmpty);
    expect(after.players[1].stores[Resource.wheat], 2);
    conserve(after);
    expect(() => MatchEngine.apply(after, chosen), throwsStateError);
  });

  test('Invasion aid proceeds clockwise, then active seat resolves', () {
    var s = fixture().copyWith(
      phase: MatchPhase.invasion,
      // The fleet needs four aid; otherwise a successful defence now skips
      // the rest of the pledge requests.
      sites: {
        0: const Site(0, Structure.town),
        2: const Site(0, Structure.town),
        4: const Site(1, Structure.town),
        6: const Site(2, Structure.town),
      },
      tactical: TacticalWindow(9, TacticalKind.invasion, 0, [1, 2]),
    );
    s = stock(stock(s, 1, {Resource.ore: 1}), 2, {Resource.ore: 1});
    for (final seat in [1, 2]) {
      expect(s.tactical!.responder, seat);
      final view = AiActionAdapter.observe(s, seat);
      final chosen = AiCardStrategy.tactical(view)!;
      expect(chosen, isA<RespondTactical>());
      s = AiActionAdapter.applySelected(s, view, chosen);
      conserve(s);
    }
    expect(s.tactical, isNull);
    s = MatchEngine.apply(s, const ResolveInvasion());
    expect(s.phase, MatchPhase.roll);
    conserve(s);
    expect(
      () => MatchEngine.apply(s, const TimeoutTactical(9, 1)),
      throwsStateError,
    );
  });

  test('open offer is countered once, then accepted or declined', () {
    var s = fixture();
    s = stock(s, 0, {Resource.ore: 1});
    s = stock(s, 1, {Resource.wheat: 2, Resource.wood: 1});
    s = s.copyWith(sites: {0: const Site(1, Structure.village)});
    s = MatchEngine.apply(
      s,
      const ProposeTrade(1, Resource.ore, 1, Resource.wheat, 2),
    );
    expect(s.offers, hasLength(1));
    // Preserve the offer while moving the fixture to the target's own turn.
    s = s.copyWith(active: 1, events: [...s.events, const EndTurn()]);
    final view = AiActionAdapter.observe(s, 1);
    final counter = AiCardStrategy.incomingOffer(view);
    expect(counter, isA<ProposeTrade>());
    expect((counter as ProposeTrade).counterOf, isNotNull);
    s = AiActionAdapter.applySelected(s, view, counter);
    expect(s.offers.single.isCounter, isTrue);
    expect(s.offers.single.proposer, 1);
    final withdrawn = MatchEngine.apply(s, WithdrawTrade(s.offers.single.id));
    expect(
      AiActionAdapter.observe(
        withdrawn,
        1,
      ).legalActions.whereType<ProposeTrade>(),
      isEmpty,
    );
    conserve(s);

    s = s.copyWith(active: 0);
    final answerView = AiActionAdapter.observe(s, 0);
    final answer = AiCardStrategy.incomingOffer(answerView);
    expect(answer, isA<RespondTrade>());
    s = AiActionAdapter.applySelected(s, answerView, answer!);
    expect(s.offers, isEmpty);
    conserve(s);
  });

  test('decisions never depend on rival hidden stores or hands', () {
    var s = cards(fixture(), 0, [held(StrategyDeck.commerce, 'resource-levy')]);
    s = stock(s, 0, {Resource.wheat: 1});
    final view = AiActionAdapter.observe(s, 0);
    final expected = AiCardStrategy.playCard(view)!.toJson();
    final players = s.players.toList();
    players[1] = players[1].copyWith(
      stores: {Resource.ore: 9},
      cards: [held(StrategyDeck.governance, 'defection')],
    );
    players[2] = players[2].copyWith(stores: {Resource.coin: 7});
    final rival = AiActionAdapter.observe(s.copyWith(players: players), 0);
    expect(AiCardStrategy.playCard(rival)!.toJson(), expected);
    expect(rival.publicOffers, isEmpty);
    expect(
      rival.legalActions.map((e) => e.toJson().toString()).toList(),
      view.legalActions.map((e) => e.toJson().toString()).toList(),
    );
  });

  test('Pass and timeout progress Governance and Invasion windows', () {
    var governance = cards(fixture(), 0, [
      held(StrategyDeck.governance, 'supply-raid'),
    ]);
    governance = stock(governance, 1, {Resource.wheat: 2});
    governance = governance.copyWith(
      tactical: TacticalWindow(11, TacticalKind.governance, 0, [
        1,
      ], card: const PlayStrategyCard(0, target: 1, receive: Resource.wheat)),
    );
    for (final decision in [
      const RespondTactical(11, 1, TacticalChoice.pass),
      const TimeoutTactical(11, 1),
    ]) {
      final resolved = MatchEngine.apply(governance, decision);
      expect(resolved.tactical, isNull);
      expect(resolved.players[0].cards, isEmpty);
      expect(resolved.players[1].stores[Resource.wheat], 1);
      conserve(resolved);
    }

    var invasion = fixture().copyWith(
      phase: MatchPhase.invasion,
      sites: {0: const Site(0, Structure.town)},
      tactical: TacticalWindow(12, TacticalKind.invasion, 0, [1, 2]),
    );
    invasion = stock(stock(invasion, 1, {Resource.wheat: 1}), 2, {
      Resource.ore: 1,
    });
    final afterTimeout = MatchEngine.apply(
      invasion,
      const TimeoutTactical(12, 1),
    );
    expect(afterTimeout.tactical!.responder, 2);
    final afterPass = MatchEngine.apply(
      afterTimeout,
      const RespondTactical(12, 2, TacticalChoice.pass),
    );
    expect(afterPass.tactical, isNull);
    expect(
      MatchEngine.apply(afterPass, const ResolveInvasion()).phase,
      MatchPhase.roll,
    );
    conserve(afterPass);
  });

  for (final resolution in ['decline', 'withdraw', 'accept']) {
    test('bot asks only once after a trade $resolution within the turn', () {
      var state = stock(fixture(), 0, {Resource.wood: 3});
      state = stock(state, 1, {Resource.ore: 2});
      state = showProduction(state, 1, [Resource.ore]);
      const proposal = ProposeTrade(1, Resource.wood, 1, Resource.ore, 1);
      state = MatchEngine.apply(state, proposal);
      final id = state.offers.single.id;
      state = MatchEngine.apply(
        state,
        resolution == 'withdraw'
            ? WithdrawTrade(id)
            : RespondTrade(1, resolution == 'accept', offerId: id),
      );
      bool isRepeat(MatchEvent event) =>
          event is ProposeTrade &&
          event.counterOf == null &&
          event.target == proposal.target &&
          event.give == proposal.give &&
          event.giveCount == proposal.giveCount &&
          event.want == proposal.want &&
          event.wantCount == proposal.wantCount;
      final view = AiActionAdapter.observe(state, 0);
      expect(view.legalActions.any(isRepeat), isFalse);
      expect(view.legalActions.whereType<ProposeTrade>(), isEmpty);
      // The history boundary permits the same terms on a later turn.
      final later = state.copyWith(events: [...state.events, const EndTurn()]);
      expect(
        AiActionAdapter.observe(later, 0).legalActions.any(isRepeat),
        isTrue,
      );
      conserve(state);
    });
  }

  test('bot trades reward recipients instead of making one-sided asks', () {
    var state = fixture().copyWith(
      sites: {0: const Site(0, Structure.village)},
    );
    state = stock(state, 0, {Resource.wood: 2});
    state = showProduction(state, 1, [Resource.wheat, Resource.ore]);
    final view = AiActionAdapter.observe(state, 0);
    final offer = AiCardStrategy.propose(view);
    expect(offer, isA<ProposeTrade>());
    final trade = offer! as ProposeTrade;
    expect(trade.target, 1);
    expect(trade.give, Resource.wood);
    expect(
      trade.giveCount,
      2,
      reason: 'One wood for a required ore/wheat is not enticing.',
    );
    expect(trade.wantCount, 1);

    // Private enemy stock and strategy cards must never change our offer.
    final players = state.players.toList();
    players[1] = players[1].copyWith(
      stores: {Resource.ore: 12},
      cards: [held(StrategyDeck.governance, 'defection')],
    );
    final changed = AiActionAdapter.observe(
      state.copyWith(players: players),
      0,
    );
    expect(AiCardStrategy.propose(changed)?.toJson(), trade.toJson());

    // Without a surplus, don't pester the same opponent with poor trades.
    final scarce = stock(state, 0, {Resource.wood: 1});
    expect(AiCardStrategy.propose(AiActionAdapter.observe(scarce, 0)), isNull);
  });

  test('bot offers surplus once and accepts a useful open trade', () {
    var proposing = fixture().copyWith(
      sites: {0: const Site(0, Structure.village)},
    );
    proposing = stock(proposing, 0, {Resource.wood: 2});
    proposing = showProduction(proposing, 1, [Resource.wheat, Resource.ore]);
    final view = AiActionAdapter.observe(proposing, 0);
    final offer = AiCardStrategy.propose(view);
    expect(offer, isA<ProposeTrade>());
    final proposal = offer! as ProposeTrade;
    expect(proposal.target, 1);
    expect(proposal.give, Resource.wood);
    expect([Resource.wheat, Resource.ore], contains(proposal.want));
    final pending = AiActionAdapter.applySelected(proposing, view, proposal);
    expect(pending.offers, hasLength(1));
    expect(AiCardStrategy.propose(AiActionAdapter.observe(pending, 0)), isNull);
    conserve(pending);

    var accepting = fixture().copyWith(
      sites: {0: const Site(1, Structure.village)},
    );
    accepting = stock(accepting, 0, {Resource.ore: 1});
    accepting = stock(accepting, 1, {Resource.wool: 2});
    accepting = MatchEngine.apply(
      accepting,
      const ProposeTrade(1, Resource.ore, 1, Resource.wool, 1),
    );
    accepting = accepting.copyWith(active: 1);
    final answerView = AiActionAdapter.observe(accepting, 1);
    final answer = AiCardStrategy.incomingOffer(answerView);
    expect(answer, isA<RespondTrade>());
    expect((answer as RespondTrade).accept, isTrue);
    final traded = AiActionAdapter.applySelected(accepting, answerView, answer);
    expect(traded.offers, isEmpty);
    expect(traded.players[1].stores[Resource.ore], 1);
    expect(traded.players[1].stores[Resource.wool], 1);
    conserve(traded);
  });
}
