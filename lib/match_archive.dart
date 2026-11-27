import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'engine/board.dart';
import 'engine/heuristic_ai.dart';
import 'engine/match.dart';

/// Independent replay blobs and metadata, with legacy monthly indexes. Only
/// completed or replaced matches are archived.
class ArchivedMatch {
  const ArchivedMatch(
    this.key,
    this.savedAt,
    this.names,
    this.round,
    this.eventCount,
    this.finished,
    this.winner, {
    this.computerSeats,
    this.botDifficulty,
  });
  final String key, savedAt;
  final List<String> names;
  final int round, eventCount;
  final bool finished;
  final String? winner;
  final Set<int>? computerSeats;
  final BotDifficulty? botDifficulty;

  String get matchup {
    final bots = computerSeats;
    if (bots == null || bots.isEmpty) return names.join(' vs ');
    final humans = [
      for (var i = 0; i < names.length; i++)
        if (!bots.contains(i)) names[i],
    ];
    final count = names.length - humans.length;
    if (count == 0) return names.join(' vs ');
    final difficulty = botDifficulty?.name;
    final label = difficulty == null ? 'Bots' : '${botDifficulty!.label} bots';
    return [...humans, '$label x$count'].join(' vs ');
  }

  String? get displayWinner {
    final name = winner;
    if (name == null || computerSeats == null) return name;
    final seat = names.indexOf(name);
    if (!computerSeats!.contains(seat)) return name;
    return botDifficulty == null ? 'Bot' : '${botDifficulty!.label} bot';
  }

  factory ArchivedMatch.fromJson(Map<String, dynamic> json) => ArchivedMatch(
    json['key'] as String,
    json['at'] as String,
    (json['names'] as List).cast<String>(),
    json['round'] as int,
    json['events'] as int,
    json['finished'] as bool,
    json['winner'] as String?,
    computerSeats: (json['computerSeats'] as List?)?.cast<int>().toSet(),
    botDifficulty: BotDifficulty.values
        .where((d) => d.name == json['botDifficulty'])
        .firstOrNull,
  );
  Map<String, Object?> toJson() => {
    'key': key,
    'at': savedAt,
    'names': names,
    'round': round,
    'events': eventCount,
    'finished': finished,
    'winner': winner,
    if (computerSeats != null) 'computerSeats': computerSeats!.toList()..sort(),
    if (botDifficulty != null) 'botDifficulty': botDifficulty!.name,
  };
}

abstract final class MatchArchive {
  static const monthsKey = 'stone_banner_archive_months_v1';
  static const _indexPrefix = 'stone_banner_archive_index_v1_';
  static const _replayPrefix = 'stone_banner_archive_replay_v1_';
  static const _metadataPrefix = 'stone_banner_archive_metadata_v1_';

  static String _metadataKey(String replayKey) =>
      '$_metadataPrefix${replayKey.substring(_replayPrefix.length)}';

  static Future<void> save(
    SharedPreferences prefs,
    MatchState match, {
    String? replay,
    Set<int>? computerSeats,
    BotDifficulty? botDifficulty,
  }) async {
    if (match.events.isEmpty) return;
    await prefs.reload();
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final month = timestamp.substring(0, 7);
    // One immutable replay per completed/abandoned state, not one ever-growing
    // array of replays and no writes while an active match is progressing.
    final bytes = replay ?? MatchEngine.exportReplay(match);
    // Content-derived suffix prevents different games with a reused seed and
    // equal event count from overwriting each other.
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(bytes)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    final key =
        '$_replayPrefix${match.seed}_${match.events.length}_${hash.toRadixString(16)}';
    final winnerSeat = MatchEngine.winner(match);
    final entry = ArchivedMatch(
      key,
      timestamp,
      [for (final player in match.players) player.id],
      match.round,
      match.events.length,
      match.phase == MatchPhase.finished,
      winnerSeat == null ? null : match.players[winnerSeat].id,
      computerSeats: computerSeats,
      botDifficulty: botDifficulty,
    );
    // An existing replay may have been archived in a different month or tab.
    if (prefs.containsKey(key) && _indexedEntries(prefs).containsKey(key)) {
      return;
    }
    // Store the replay first, then independent metadata. A stale monthly
    // index or interrupted write can no longer hide a saved replay.
    if (!prefs.containsKey(key) && !await prefs.setString(key, bytes)) {
      throw StateError('Could not archive the match replay.');
    }
    if (!await prefs.setString(_metadataKey(key), jsonEncode(entry.toJson()))) {
      throw StateError('Could not archive the match metadata.');
    }
    // Keep writing legacy indexes for clients running an older build.
    final indexKey = '$_indexPrefix$month';
    final previous = prefs.getStringList(indexKey) ?? [];
    if (!await prefs.setStringList(indexKey, [
      jsonEncode(entry.toJson()),
      ...previous,
    ])) {
      throw StateError('Could not update match history index.');
    }
    final months = prefs.getStringList(monthsKey) ?? [];
    if (!months.contains(month) &&
        !await prefs.setStringList(monthsKey, [...months, month]..sort())) {
      throw StateError('Could not update match history months.');
    }
  }

  static Map<String, ArchivedMatch> _indexedEntries(SharedPreferences prefs) {
    final entries = <String, ArchivedMatch>{};
    void add(String raw) {
      try {
        final entry = ArchivedMatch.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (entry.key.startsWith(_replayPrefix) &&
            prefs.containsKey(entry.key)) {
          final previous = entries[entry.key];
          if (previous == null ||
              entry.savedAt.compareTo(previous.savedAt) < 0) {
            entries[entry.key] = entry;
          }
        }
      } on Object {
        // A damaged record must not hide unrelated matches.
      }
    }

    // Enumerate actual keys rather than trusting the mutable month manifest.
    for (final key in prefs.getKeys().where(
      (k) => k.startsWith(_indexPrefix),
    )) {
      try {
        for (final raw in prefs.getStringList(key) ?? <String>[]) {
          add(raw);
        }
      } on Object {
        // Continue with independent records and replay recovery.
      }
    }
    for (final key in prefs.getKeys().where(
      (k) => k.startsWith(_metadataPrefix),
    )) {
      try {
        final raw = prefs.getString(key);
        if (raw != null) add(raw);
      } on Object {
        // Continue with the replay itself.
      }
    }
    return entries;
  }

  static Future<List<ArchivedMatch>> list(SharedPreferences prefs) async {
    await prefs.reload();
    final entries = _indexedEntries(prefs);
    for (final key in prefs.getKeys().where(
      (k) => k.startsWith(_replayPrefix),
    )) {
      if (entries.containsKey(key)) continue;
      try {
        final match = MatchEngine.importReplay(prefs.getString(key)!);
        final winner = MatchEngine.winner(match);
        entries[key] = ArchivedMatch(
          key,
          '', // Legacy orphan replays do not contain a date or bot settings.
          [for (final player in match.players) player.id],
          match.round,
          match.events.length,
          match.phase == MatchPhase.finished,
          winner == null ? null : match.players[winner].id,
        );
      } on Object {
        // An unreadable replay cannot be reconstructed; keep its stored data.
      }
    }
    return entries.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  /// Portable, versioned archive containing the original replay strings.
  static String exportAll(
    SharedPreferences prefs,
    List<ArchivedMatch> entries,
  ) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'matches': [
        for (final entry in entries)
          {
            ...entry.toJson(),
            'replay':
                replay(prefs, entry) ??
                (throw StateError('Missing replay for ${entry.key}')),
          },
      ],
    });
  }

  static String? replay(SharedPreferences prefs, ArchivedMatch entry) =>
      prefs.getString(entry.key);
}

/// Only used in debug builds; each immutable record is appended to a bounded
/// 32-event chunk, never a single unbounded match-wide JSON array.
abstract final class DebugMatchLog {
  static Future<void> append(
    SharedPreferences prefs,
    MatchState before,
    MatchState after,
  ) async {
    if (after.events.length != before.events.length + 1 ||
        before.seed != after.seed) {
      return;
    }
    final ordinal = before.events.length;
    final chunk = ordinal ~/ 32;
    final key = 'stone_banner_debug_event_v1_${after.seed}_$chunk';
    final raw = prefs.getString(key);
    final records = raw == null
        ? <dynamic>[]
        : jsonDecode(raw) as List<dynamic>;
    if (records.any(
      (record) => record is Map && record['ordinal'] == ordinal,
    )) {
      return;
    }
    final changes = <String, Map<String, int>>{};
    final cardChanges = <String, Map<String, List<String>>>{};
    for (var player = 0; player < after.players.length; player++) {
      final goods = <String, int>{};
      for (final resource in Resource.values) {
        final delta =
            (after.players[player].stores[resource] ?? 0) -
            (before.players[player].stores[resource] ?? 0);
        if (delta != 0) goods[resource.name] = delta;
      }
      if (goods.isNotEmpty) changes['$player'] = goods;
      final prior = before.players[player].cards
          .map((c) => '${c.track.name}:${c.index}')
          .toSet();
      final next = after.players[player].cards
          .map((c) => '${c.track.name}:${c.index}')
          .toSet();
      if (prior.difference(next).isNotEmpty ||
          next.difference(prior).isNotEmpty) {
        cardChanges['$player'] = {
          'gained': next.difference(prior).toList(),
          'spent': prior.difference(next).toList(),
        };
      }
    }
    records.add({
      'ordinal': ordinal,
      'at': DateTime.now().toUtc().toIso8601String(),
      'round': before.round,
      'active': before.active,
      'actor': before.actingSeat,
      'event': after.events.last.toJson(),
      'goodsDelta': changes,
      'cardsDelta': cardChanges,
      'invasionAidDelta': after.invasionAid - before.invasionAid,
      if (after.lastInvasion != before.lastInvasion)
        'invasionResult': after.lastInvasion,
    });
    if (records.length > 32) records.removeRange(0, records.length - 32);
    if (!await prefs.setString(key, jsonEncode(records))) {
      throw StateError('Could not write debug game log.');
    }
    // Logs are forensic diagnostics, not the canonical replay. Keep the last
    // 4096 events per seed without unbounded device-storage growth.
    if (ordinal > 0 && ordinal % 32 == 0 && chunk >= 128) {
      await prefs.remove(
        'stone_banner_debug_event_v1_${after.seed}_${chunk - 128}',
      );
    }
  }
}
