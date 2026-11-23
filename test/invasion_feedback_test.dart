import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/invasion_feedback.dart';

import 'stage5_widget_test.dart' show drafted;

MatchState villagesOnly() {
  final base = drafted();
  return base.copyWith(
    sites: {
      for (final entry in base.sites.entries)
        entry.key: Site(entry.value.owner, Structure.village),
    },
  );
}

void main() {
  test('early fleet leaves Villages intact and explains why', () {
    final before = villagesOnly().copyWith(
      phase: MatchPhase.invasion,
      reaverPressure: 3,
    );
    final forecast = MatchEngine.invasionForecast(before);
    final after = MatchEngine.apply(before, const ResolveInvasion());
    expect(after.lastInvasion, forecast);
    expect(forecast, contains('No damage: only Villages remain'));
    expect(after.sites, before.sites);
    expect(
      after.players.map((p) => p.stores),
      before.players.map((p) => p.stores),
    );
    expect(after.invasions, before.invasions + 1);
    expect(after.reaverPressure, 0);
    expect(before.reaverPressure, 3);
  });

  test('forecast and result explain Town loss, shield, and Honour', () {
    final base = villagesOnly().copyWith(
      phase: MatchPhase.invasion,
      reaverPressure: 3,
    );
    final v = base.sites.keys.first;
    final town = base.copyWith(
      sites: {...base.sites, v: Site(0, Structure.town)},
    );
    for (final state in [
      town,
      town.copyWith(fortified: {v}),
      base.copyWith(
        guards: {
          v: const GuardPiece(0, GuardRank.champion, true, -1),
          v + 1: const GuardPiece(0, GuardRank.warden, true, -1),
        },
      ),
    ]) {
      expect(
        MatchEngine.invasionForecast(state),
        MatchEngine.apply(state, const ResolveInvasion()).lastInvasion,
      );
    }
    expect(
      MatchEngine.invasionForecast(town),
      contains('town downgraded to village'),
    );
    expect(MatchEngine.invasionForecast(town), contains('(-1 Renown)'));
    // A single upgraded village now has strength 1, so one Fort
    // is enough to repel the assault instead of being destroyed.
    expect(
      MatchEngine.invasionForecast(town.copyWith(fortified: {v})),
      contains('Defended 1–1'),
    );
  });

  testWidgets(
    'resolution stays visible across following turns until dismissed',
    (tester) async {
      final before = villagesOnly().copyWith(
        phase: MatchPhase.invasion,
        reaverPressure: 3,
      );
      Future<void> show(MatchState state) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: InvasionFeedback(state: state)),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(before);
      expect(find.text('Invasion resolved'), findsNothing);
      final after = MatchEngine.apply(before, const ResolveInvasion());
      await show(after);
      expect(find.text('Invasion resolved'), findsOneWidget);
      expect(find.text(after.lastInvasion), findsOneWidget);
      await show(after.copyWith(active: 1));
      expect(find.text('Invasion resolved'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await show(after.copyWith(active: 2));
      expect(find.text('Invasion resolved'), findsNothing);
    },
  );
}
