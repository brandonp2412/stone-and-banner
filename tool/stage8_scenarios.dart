import 'dart:convert';
import 'dart:io';

import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/engine/simulation.dart';
import 'package:stone_and_banner/replay_codes.dart';

/// Reproducible mid-game replay checkpoints for release-device UX smoke tests.
void main() {
  final directory = Directory('/tmp/stone_banner_stage8_scenarios')
    ..createSync(recursive: true);
  final wanted = <String>{
    'develop',
    'card',
    'bandit',
    'upgrade',
    'capital',
    'win',
  };
  final found = <String, Map<String, Object?>>{};
  for (var seed = 1000; seed < 1040 && found.length < wanted.length; seed++) {
    final result = BalanceSimulation.run(seed: seed, maxRounds: 90);
    var before = MatchEngine.newGame(
      [for (var i = 0; i < 3; i++) 'Bot-$i'],
      seed,
      boardSeed: seed * 7 + 11,
    );
    for (final event in result.state.events) {
      final next = MatchEngine.apply(before, event);
      final category = switch (event) {
        DevelopTown() => 'develop',
        PlayStrategyCard() => 'card',
        MoveBandit() => 'bandit',
        UpgradeSite() => 'upgrade',
        _ => null,
      };
      final candidates = [
        ?category,
        if (event is UpgradeSite &&
            before.sites[event.vertex]?.structure.name == 'town')
          'capital',
        if (MatchEngine.winner(next) != null &&
            MatchEngine.winner(before) == null)
          'win',
      ];
      for (final label in candidates) {
        if (found.containsKey(label)) continue;
        final replay = MatchEngine.exportReplay(before);
        final file = File('${directory.path}/$label.json');
        file.writeAsStringSync(replay);
        final code = ReplayCodes.compact(replay);
        File('${directory.path}/$label.code').writeAsStringSync(code);
        found[label] = {
          'file': file.path,
          'seed': seed,
          'events': before.events.length,
          'action': event.runtimeType.toString(),
          'active': before.current.id,
          'phase': before.phase.name,
          'bytes': replay.length,
          'compactBytes': code.length,
          'winnerAfter': MatchEngine.winner(next),
          if (event is UpgradeSite)
            'upgrade': {
              'vertex': event.vertex,
              'from': before.sites[event.vertex]?.structure.name,
              'to': next.sites[event.vertex]?.structure.name,
            },
          if (label == 'bandit')
            'victimTiles': [
              for (var i = 0; i < before.board.tiles.length; i++)
                if (i != before.banditTile &&
                    MatchEngine.banditVictims(before, i).isNotEmpty)
                  i,
            ],
        };
      }
      before = next;
    }
  }
  File('${directory.path}/manifest.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(found));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(found));
  if (found.length < wanted.length) exitCode = 1;
}
