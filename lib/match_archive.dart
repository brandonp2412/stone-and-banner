import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'engine/board.dart';
import 'engine/match.dart';

/// Small month indexes with individual immutable replay blobs. Autosaves never
/// update an archive: only completed or replaced matches are archived.
class ArchivedMatch {
  const ArchivedMatch(
    this.key,
    this.savedAt,
    this.names,
    this.round,
    this.eventCount,
    this.finished,
    this.winner,
  );
  final String key, savedAt;
  final List<String> names;
  final int round, eventCount;
  final bool finished;
  final String? winner;

  factory ArchivedMatch.fromJson(Map<String, dynamic> json) => ArchivedMatch(
    json['key'] as String,
    json['at'] as String,
    (json['names'] as List).cast<String>(),
    json['round'] as int,
    json['events'] as int,
    json['finished'] as bool,
    json['winner'] as String?,
  );
  Map<String, Object?> toJson() => {
    'key': key,
    'at': savedAt,
    'names': names,
    'round': round,
    'events': eventCount,
    'finished': finished,
    'winner': winner,
  };
}

abstract final class MatchArchive {
  static const monthsKey = 'stone_banner_archive_months_v1';
  static const _indexPrefix = 'stone_banner_archive_index_v1_';
  static const _replayPrefix = 'stone_banner_archive_replay_v1_';

  static Future<void> save(
    SharedPreferences prefs,
    MatchState match, {
    String? replay,
  }) async {
    if (match.events.isEmpty) return;
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
    );
    final indexKey = '$_indexPrefix$month';
    final previous = prefs.getStringList(indexKey) ?? [];
    if (previous.any((raw) {
      try {
        return (jsonDecode(raw) as Map)['key'] == key;
      } on Object {
        return false;
      }
    })) {
      return;
    }
    // Commit blob before indexing, so interrupted writes cannot create a
    // manifest entry pointing at absent data.
    if (!prefs.containsKey(key) && !await prefs.setString(key, bytes)) {
      throw StateError('Could not archive the match replay.');
    }
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

  static Future<List<ArchivedMatch>> list(SharedPreferences prefs) async {
    final result = <ArchivedMatch>[];
    final months = [...?prefs.getStringList(monthsKey)]
      ..sort((a, b) => b.compareTo(a));
    for (final month in months) {
      for (final raw
          in prefs.getStringList('$_indexPrefix$month') ?? <String>[]) {
        try {
          final entry = ArchivedMatch.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
          if (prefs.containsKey(entry.key)) result.add(entry);
        } on Object {
          // Corrupt metadata must not hide other saved matches.
        }
      }
    }
    result.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return result;
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
