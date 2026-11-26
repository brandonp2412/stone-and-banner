import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/match.dart';
import '../match_archive.dart';
import 'compact_layout.dart';
import 'match_screen.dart';

/// Reviewing an archive never replaces the live autosave.
class MatchHistoryPage extends StatefulWidget {
  const MatchHistoryPage({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<MatchHistoryPage> createState() => _MatchHistoryPageState();
}

class _MatchHistoryPageState extends State<MatchHistoryPage> {
  late final Future<List<ArchivedMatch>> _history = MatchArchive.list(
    widget.prefs,
  );
  bool _exporting = false;

  Future<void> _export(List<ArchivedMatch> history) async {
    setState(() => _exporting = true);
    try {
      final json = MatchArchive.exportAll(widget.prefs, history);
      final now = DateTime.now().toIso8601String().substring(0, 10);
      final saved = await FilePicker.saveFile(
        fileName: 'stone-and-banner-history-$now.json',
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
        dialogTitle: 'Export match history',
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported ${history.length} ${history.length == 1 ? 'match' : 'matches'}.',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not export match history.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _review(ArchivedMatch entry) {
    final replay = MatchArchive.replay(widget.prefs, entry);
    if (replay == null) return;
    try {
      final restored = MatchEngine.importReplay(replay);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: MatchView(
                state: restored,
                onEvent: (_) {},
                observing: true,
                visibleSeat: 0,
                computerSeats: entry.computerSeats ?? const {},
                // Legacy archives did not record bot seats.
                viewingSeat: entry.computerSeats == null ? 0 : null,
                onHome: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      );
    } on Object {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cannot open this replay.')));
    }
  }

  static DateTime? _localDate(ArchivedMatch entry) =>
      DateTime.tryParse(entry.savedAt)?.toLocal();

  String _day(BuildContext context, ArchivedMatch entry) {
    final date = _localDate(entry);
    return date == null
        ? 'Unknown date'
        : MaterialLocalizations.of(context).formatFullDate(date);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ArchivedMatch>>(
    future: _history,
    builder: (context, snapshot) {
      final history = snapshot.data ?? const <ArchivedMatch>[];
      final compact = MediaQuery.sizeOf(context).width < 900;
      final action = IconButton(
        key: const ValueKey('export-all-history'),
        tooltip: 'Export all matches',
        onPressed: history.isEmpty || _exporting
            ? null
            : () => _export(history),
        icon: const Icon(Icons.download_rounded),
      );
      return Scaffold(
        appBar: compact
            ? null
            : AppBar(title: const Text('Match history'), actions: [action]),
        body: SafeArea(
          child: Column(
            children: [
              if (compact)
                CompactPageHeader(
                  title: 'Match history',
                  onBack: () => Navigator.of(context).pop(),
                  actions: [action],
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: snapshot.hasError
                        ? const Center(
                            child: Text('Match history could not be read.'),
                          )
                        : !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : history.isEmpty
                        ? const _EmptyHistory()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: history.length + 1,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                final finished = history
                                    .where((e) => e.finished)
                                    .length;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    '${history.length} ${history.length == 1 ? 'match' : 'matches'} · $finished finished',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                );
                              }
                              final entry = history[index - 1];
                              final day = _day(context, entry);
                              final newDay =
                                  index == 1 ||
                                  day != _day(context, history[index - 2]);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (newDay)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        4,
                                        8,
                                        4,
                                        8,
                                      ),
                                      child: Text(
                                        day,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                    ),
                                  _HistoryCard(
                                    key: ValueKey('archived-${entry.key}'),
                                    entry: entry,
                                    date: _localDate(entry),
                                    onReview: () => _review(entry),
                                    onCopy: () async {
                                      final replay = MatchArchive.replay(
                                        widget.prefs,
                                        entry,
                                      );
                                      if (replay != null) {
                                        await Clipboard.setData(
                                          ClipboardData(text: replay),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.history_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          'No archived matches yet.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text('Finished and replaced games appear here.'),
      ],
    ),
  );
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    super.key,
    required this.entry,
    required this.date,
    required this.onReview,
    required this.onCopy,
  });

  final ArchivedMatch entry;
  final DateTime? date;
  final VoidCallback onReview, onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final time = date == null
        ? ''
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(date!),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    final outcome = entry.winner != null
        ? '${entry.winner} won'
        : entry.finished
        ? 'Finished'
        : 'Replaced';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: entry.finished
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      entry.finished
                          ? Icons.emoji_events_outlined
                          : Icons.history_rounded,
                      color: entry.finished
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        outcome,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.names.join(' vs '),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (time.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Round ${entry.round} · ${entry.eventCount} ${entry.eventCount == 1 ? 'action' : 'actions'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy replay',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_outlined, size: 19),
                ),
                TextButton(onPressed: onReview, child: const Text('Review')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
