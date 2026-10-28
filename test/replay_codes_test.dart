import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/replay_codes.dart';

void main() {
  test('compact replay restores identical deterministic state', () {
    var state = MatchEngine.newGame(['Ada', 'Ben', 'Cora'], 1000);
    final village = MatchEngine.legalVertices(state).first;
    state = MatchEngine.apply(state, PlaceVillage(village));
    final raw = MatchEngine.exportReplay(state);
    final code = ReplayCodes.compact(raw);
    expect(code, startsWith(ReplayCodes.prefix));
    expect(
      MatchEngine.snapshot(MatchEngine.importReplay(ReplayCodes.expand(code))),
      MatchEngine.snapshot(state),
    );
    expect(ReplayCodes.expand(raw), raw);
    expect(
      ReplayCodes.expand(code.replaceAll('-', '+').replaceAll('_', '/')),
      raw,
    );
  });

  test('rejects invalid, oversized and decompression-bomb codes', () {
    expect(() => ReplayCodes.expand('sbz1:!'), throwsFormatException);
    expect(
      () => ReplayCodes.expand('sbz1:${'a' * 160000}'),
      throwsFormatException,
    );
    final bomb =
        'sbz1:${base64Url.encode(gzip.encode(utf8.encode('X' * (1024 * 1024 + 1))))}';
    expect(() => ReplayCodes.expand(bomb), throwsFormatException);
  });
}
