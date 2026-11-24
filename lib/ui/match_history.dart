import 'compact_layout.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/match.dart';
import '../match_archive.dart';
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: MediaQuery.sizeOf(context).width < 900
        ? null
        : AppBar(title: const Text('Match history')),
    body: Column(
      children: [
        if (MediaQuery.sizeOf(context).width < 900)
          CompactPageHeader(
            title: 'Match history',
            onBack: () => Navigator.of(context).pop(),
          ),
        Expanded(
          child: FutureBuilder<List<ArchivedMatch>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Match history could not be read.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final history = snapshot.data!;
              if (history.isEmpty) {
                return const Center(child: Text('No archived matches yet.'));
              }
              return ListView.builder(
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final entry = history[index];
                  final players = entry.names.join(' vs ');
                  return ListTile(
                    dense: isCompactLandscape(context),
                    visualDensity: isCompactLandscape(context)
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    key: ValueKey('archived-${entry.key}'),
                    title: Text('$players · Round ${entry.round}'),
                    subtitle: Text(
                      '${entry.savedAt.substring(0, 16).replaceFirst('T', ' ')} UTC · '
                      '${entry.finished ? 'Finished' : 'Replaced'} · ${entry.eventCount} actions'
                      '${entry.winner == null ? '' : ' · Winner: ${entry.winner}'}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Copy replay',
                          onPressed: () {
                            final replay = MatchArchive.replay(
                              widget.prefs,
                              entry,
                            );
                            if (replay != null) {
                              Clipboard.setData(ClipboardData(text: replay));
                            }
                          },
                          icon: const Icon(Icons.copy),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            final replay = MatchArchive.replay(
                              widget.prefs,
                              entry,
                            );
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
                                        computerSeats:
                                            entry.computerSeats ?? const {},
                                        // Legacy archives did not record bot seats.
                                        // Review them from the original seat-zero perspective.
                                        viewingSeat: entry.computerSeats == null
                                            ? 0
                                            : null,
                                        onHome: () =>
                                            Navigator.of(context).pop(),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            } on Object {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cannot open this replay.'),
                                ),
                              );
                            }
                          },
                          child: const Text('Review'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
