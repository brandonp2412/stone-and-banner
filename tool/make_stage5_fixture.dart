import 'dart:io';

import 'package:stone_and_banner/engine/match.dart';

void main() {
  for (var seed = 1; seed <= 500; seed++) {
    var s = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], seed);
    for (var i = 0; i < 6; i++) {
      s = MatchEngine.apply(
        s,
        PlaceVillage(MatchEngine.legalVertices(s).first),
      );
      s = MatchEngine.apply(s, PlaceRoad(MatchEngine.legalEdges(s).first));
    }
    for (var turn = 0; turn < 18; turn++) {
      if (s.phase == MatchPhase.invasion) {
        if (s.tactical != null) {
          final path = File('test/fixtures/stage5_invasion_reaction.json');
          path.parent.createSync(recursive: true);
          path.writeAsStringSync(MatchEngine.exportReplay(s));
          stdout.writeln(
            [
              'seed:',
              seed,
              'window:',
              s.tactical!.id,
              'responder:',
              s.tactical!.responder,
              'events:',
              s.events.length,
              'bytes:',
              path.lengthSync(),
            ].join(' '),
          );
          return;
        }
        s = MatchEngine.apply(s, const ResolveInvasion());
      }
      if (s.phase == MatchPhase.roll) s = MatchEngine.roll(s);
      if (s.phase == MatchPhase.bandit) {
        s = MatchEngine.apply(
          s,
          MoveBandit((s.banditTile + 1) % s.board.tiles.length),
        );
      }
      if (s.phase == MatchPhase.actions) {
        s = MatchEngine.apply(s, const EndTurn());
      }
    }
  }
  throw StateError('No eligible seeded aid fixture found.');
}
