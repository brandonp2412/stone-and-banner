import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/ai.dart';
import 'package:stone_and_banner/engine/ai_cards.dart';
import 'package:stone_and_banner/engine/balance.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

MatchState _raid({
  MatchBalance balance = MatchBalance.baseline,
  int invasions = 0,
  int honour = 0,
}) {
  var state = MatchEngine.newGame(
    ['Ada', 'Ben', 'Cora'],
    54822,
    balance: balance,
  );
  final players = state.players.toList();
  players[0] = players[0].copyWith(guardianHonour: honour);
  state = state.copyWith(
    players: players,
    phase: MatchPhase.invasion,
    sites: {0: const Site(0, Structure.town)},
    guards: {1: const GuardPiece(0, GuardRank.sentinel, true, -1)},
    invasions: invasions,
  );
  return state;
}

void main() {
  test('first raid is unchanged; subsequent raids need one more defence', () {
    final first = _raid();
    expect(MatchEngine.invasionStrength(first), 1);
    expect(MatchEngine.defenceStrength(first), 1);
    final defended = MatchEngine.apply(first, const ResolveInvasion());
    expect(defended.lastInvasion, startsWith('Defended 1–1'));
    expect(defended.players[0].guardianHonour, 1);

    final second = _raid(invasions: 1);
    expect(MatchEngine.invasionStrength(second), 2);
    final damaged = MatchEngine.apply(second, const ResolveInvasion());
    expect(damaged.lastInvasion, contains('Invasion 2–1'));
    expect(damaged.sites[0]!.structure, Structure.village);
    expect(damaged.players[0].guardianHonour, 0);
    expect(MatchEngine.invasionStrength(second.copyWith(sites: {})), 0);
  });

  test('Guardian Honour stops at two without suppressing a defence', () {
    final defended = MatchEngine.apply(
      _raid(honour: 2),
      const ResolveInvasion(),
    );
    expect(defended.players[0].guardianHonour, 2);
    expect(defended.lastInvasion, contains('Honour limit'));
    expect(defended.lastInvasion, startsWith('Defended'));
  });

  test('older replays without the two balance fields retain their rules', () {
    final legacy = _raid(balance: MatchBalance.legacy, invasions: 1, honour: 2);
    expect(MatchEngine.invasionStrength(legacy), 1);
    final before = MatchEngine.exportReplay(
      MatchEngine.newGame(
        ['Ada', 'Ben', 'Cora'],
        54822,
        balance: MatchBalance.legacy,
      ),
    );
    final decoded = jsonDecode(before) as Map<String, dynamic>;
    final oldBalance = decoded['balance'] as Map<String, dynamic>;
    oldBalance.remove('raidBonusAfterFirst');
    oldBalance.remove('guardianHonourCap');
    final reimported = MatchEngine.importReplay(jsonEncode(decoded));
    expect(reimported.balance.raidBonusAfterFirst, 0);
    expect(reimported.balance.guardianHonourCap, 0);
    expect(MatchBalance.fromJson(null).toJson(), MatchBalance.legacy.toJson());
    final award = MatchEngine.apply(legacy, const ResolveInvasion());
    expect(award.players[0].guardianHonour, 3);
  });

  test('AI responds to the best feasible offer, not the oldest bad one', () {
    var state = MatchEngine.newGame([
      'Ada',
      'Ben',
      'Cora',
    ], 75612).copyWith(phase: MatchPhase.actions, active: 1);
    final players = state.players.toList();
    players[1] = players[1].copyWith(
      stores: {Resource.wood: 1, Resource.ore: 1},
    );
    state = state.copyWith(
      players: players,
      offers: [
        const TradeProposal(3, 0, 1, Resource.ore, 1, Resource.wood, 1),
        const TradeProposal(4, 2, 1, Resource.wheat, 2, Resource.ore, 1),
      ],
    );
    final view = AiActionAdapter.observe(state, 1);
    final chosen = AiCardStrategy.incomingOffer(view);
    expect(chosen, isA<RespondTrade>());
    expect((chosen as RespondTrade).accept, isTrue);
    expect(chosen.offerId, 4);
  });
}
