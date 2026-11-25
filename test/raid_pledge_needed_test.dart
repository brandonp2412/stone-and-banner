import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/balance.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

MatchState approachingRaid({
  required Map<int, Site> sites,
  Set<int> forts = const {},
  MatchBalance balance = MatchBalance.baseline,
}) {
  return MatchEngine.newGame(
    ['Ana', 'Ben', 'Cam'],
    729,
    balance: balance,
  ).copyWith(
    phase: MatchPhase.actions,
    active: 2,
    reaverPressure: 5,
    sites: sites,
    fortified: forts,
  );
}

void main() {
  test('a raid already defended has no pledge window', () {
    final before = approachingRaid(
      sites: {0: const Site(0, Structure.town)},
      forts: {0},
    );
    expect(MatchEngine.defenceStrength(before), 1);
    expect(MatchEngine.invasionStrength(before), 1);
    final raid = MatchEngine.apply(before, const EndTurn());
    expect(raid.phase, MatchPhase.invasion);
    expect(raid.tactical, isNull);
    final resolved = MatchEngine.apply(raid, const ResolveInvasion());
    expect(resolved.invasions, 1);
    expect(resolved.lastInvasion, contains('Defended'));
  });

  test('one sufficient pledge closes remaining requests immediately', () {
    var before = approachingRaid(
      sites: {
        0: const Site(0, Structure.town),
        2: const Site(1, Structure.town),
      },
    );
    final players = before.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.ore: 1});
    before = before.copyWith(
      players: players,
      bank: {...before.bank, Resource.ore: before.bank[Resource.ore]! - 1},
    );
    final raid = MatchEngine.apply(before, const EndTurn());
    expect(raid.tactical?.responder, 0);
    final pledged = MatchEngine.apply(
      raid,
      RespondTactical(
        raid.tactical!.id,
        0,
        TacticalChoice.aid,
        good: Resource.ore,
      ),
    );
    expect(MatchEngine.invasionStrength(pledged), 2);
    expect(pledged.invasionAid, 2);
    expect(pledged.tactical, isNull);
    expect(MatchEngine.apply(pledged, const ResolveInvasion()).invasions, 1);
  });

  test('aid can only cover a two-point shortfall in a new match', () {
    const sites = {
      0: Site(0, Structure.town),
      2: Site(1, Structure.town),
      4: Site(2, Structure.town),
    };
    final raid = MatchEngine.apply(
      approachingRaid(sites: sites),
      const EndTurn(),
    );
    expect(MatchEngine.invasionStrength(raid), 3);
    expect(raid.tactical, isNull);
    expect(
      MatchEngine.apply(raid, const ResolveInvasion()).lastInvasion,
      startsWith('Invasion 3–0'),
    );

    final legacyRaid = MatchEngine.apply(
      approachingRaid(sites: sites, balance: MatchBalance.fromJson({})),
      const EndTurn(),
    );
    expect(legacyRaid.tactical?.kind, TacticalKind.invasion);
    expect(MatchBalance.fromJson(raid.balance.toJson()).raidAidCap, 2);
  });

  test('wheat followed by ore cannot exceed the shared aid cap', () {
    final before = approachingRaid(
      sites: {
        0: const Site(0, Structure.town),
        2: const Site(1, Structure.town),
        4: const Site(2, Structure.town),
      },
      forts: {0},
    );
    final players = before.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wheat: 1});
    players[1] = players[1].copyWith(stores: {Resource.ore: 1});
    final raid = MatchEngine.apply(
      before.copyWith(
        players: players,
        bank: {
          ...before.bank,
          Resource.wheat: before.bank[Resource.wheat]! - 1,
          Resource.ore: before.bank[Resource.ore]! - 1,
        },
      ),
      const EndTurn(),
    );
    final wheat = MatchEngine.apply(
      raid,
      RespondTactical(
        raid.tactical!.id,
        0,
        TacticalChoice.aid,
        good: Resource.wheat,
      ),
    );
    expect(wheat.invasionAid, 1);
    final ore = MatchEngine.apply(
      wheat,
      RespondTactical(
        wheat.tactical!.id,
        1,
        TacticalChoice.aid,
        good: Resource.ore,
      ),
    );
    expect(ore.invasionAid, 2);
    expect(ore.tactical, isNull);
    expect(
      MatchEngine.apply(ore, const ResolveInvasion()).lastInvasion,
      startsWith('Defended 3–3'),
    );
  });

  test('undefended raids still request help', () {
    final raid = MatchEngine.apply(
      approachingRaid(sites: {0: const Site(0, Structure.town)}),
      const EndTurn(),
    );
    expect(raid.tactical?.kind, TacticalKind.invasion);
    expect(raid.tactical?.responder, 0);
  });
}
