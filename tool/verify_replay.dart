import 'dart:convert';
import 'dart:io';

import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/replay_codes.dart';

/// Audit a genuine saved replay at every event, optionally retaining a prefix.
/// dart run tool/verify_replay.dart REPLAY_JSON_OR_CODE [EARLIER_REPLAY]
void main(List<String> args) {
  try {
    if (args.isEmpty || args.length > 2) {
      throw ArgumentError('Provide a replay file and optional earlier replay.');
    }
    MatchState read(String path) => MatchEngine.importReplay(
      ReplayCodes.expand(File(path).readAsStringSync().trim()),
    );
    final saved = read(args.first);
    var state = MatchEngine.newGame(
      saved.players.map((p) => p.id).toList(),
      saved.seed,
      boardSeed: saved.board.seed,
      balance: saved.balance,
      cardDeckVersion: saved.cardDeckVersion,
      invasionInvitesFromEvent: saved.invasionInvitesFromEvent,
      raidPledgeFixFromEvent: saved.raidPledgeFixFromEvent,
      raidInterval: saved.raidInterval,
      turnOrder: saved.turnOrder,
    );
    final eventTypes = <String, int>{};
    _verifySupply(state);
    for (final event in saved.events) {
      try {
        state = MatchEngine.apply(state, event);
      } catch (error) {
        throw StateError(
          "Event ${state.events.length + 1}: ${event.toJson()}: $error",
        );
      }
      _verifySupply(state);
      final type = event.toJson()['type']! as String;
      eventTypes.update(type, (n) => n + 1, ifAbsent: () => 1);
    }
    if (MatchEngine.snapshot(state) != MatchEngine.snapshot(saved)) {
      throw StateError('Event-by-event reduction differs from imported state.');
    }
    final exported = MatchEngine.exportReplay(state);
    if (exported !=
        MatchEngine.exportReplay(MatchEngine.importReplay(exported))) {
      throw StateError('Export/import changed canonical replay bytes.');
    }
    int? prefixEvents;
    if (args.length == 2) {
      final prior = read(args[1]);
      final before = jsonDecode(MatchEngine.exportReplay(prior)) as Map;
      final after = jsonDecode(exported) as Map;
      final oldEvents = before.remove('events') as List;
      final newEvents = after.remove('events') as List;
      if (jsonEncode(before) != jsonEncode(after) ||
          jsonEncode(oldEvents) !=
              jsonEncode(newEvents.take(oldEvents.length).toList())) {
        throw StateError('Earlier saved events were changed or lost.');
      }
      prefixEvents = oldEvents.length;
    }
    final winner = MatchEngine.winner(state);
    stdout.writeln(
      jsonEncode({
        'events': state.events.length,
        'round': state.round,
        'phase': state.phase.name,
        'winner': winner == null ? null : state.players[winner].id,
        'scores': [
          for (var i = 0; i < state.players.length; i++)
            MatchEngine.score(state, i),
        ],
        'eventTypes': eventTypes,
        'supplyAndCardCopiesCheckedStates': state.events.length + 1,
        'canonicalRoundTripBytesEqual': true,
        'preservedPrefixEvents': prefixEvents,
      }),
    );
  } on Object catch (error) {
    stderr.writeln('Replay audit failed: $error');
    exitCode = 1;
  }
}

void _verifySupply(MatchState state) {
  for (final good in Resource.values) {
    final amounts = [
      state.bank[good] ?? 0,
      for (final player in state.players) player.stores[good] ?? 0,
      // Standing offers do not reserve goods; they transfer on acceptance.
    ];
    if (amounts.any((amount) => amount < 0) ||
        amounts.fold<int>(0, (a, b) => a + b) != MatchEngine.bankSupply) {
      throw StateError(
        'Goods accounting failed at event ${state.events.length}.',
      );
    }
  }
  for (final track in StrategyDeck.values) {
    final copies = [
      ...state.drawPiles[track]!,
      ...state.discardPiles[track]!,
      for (final player in state.players)
        for (final card in player.cards)
          if (card.track == track) card.index,
    ]..sort();
    final expected = List.generate(
      StrategyCards.deckForVersion(track, state.cardDeckVersion).length,
      (i) => i,
    );
    if (jsonEncode(copies) != jsonEncode(expected)) {
      throw StateError(
        'Card accounting failed at event ${state.events.length}.',
      );
    }
  }
}
