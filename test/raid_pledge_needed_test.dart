import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';

MatchState approachingRaid({
  required Map<int, Site> sites,
  Set<int> forts = const {},
}) {
  return MatchEngine.newGame(['Ana', 'Ben', 'Cam'], 729).copyWith(
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

  test('undefended raids still request help', () {
    final raid = MatchEngine.apply(
      approachingRaid(sites: {0: const Site(0, Structure.town)}),
      const EndTurn(),
    );
    expect(raid.tactical?.kind, TacticalKind.invasion);
    expect(raid.tactical?.responder, 0);
  });
}
