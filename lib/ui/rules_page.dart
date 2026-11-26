import 'package:flutter/material.dart';

import 'compact_layout.dart';
import 'rules_reference.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  static final _wordBreak = RegExp(r'[^a-z0-9]+');

  String _normalize(String text) =>
      text.toLowerCase().replaceAll(_wordBreak, ' ').trim();

  void _updateSearch() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {});
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalize(_search.text);
    final terms = query.isEmpty ? const <String>[] : query.split(' ');
    final searching = terms.isNotEmpty;
    final sections = <RuleSection>[
      for (final section in rulesReference)
        if (!searching)
          section
        else
          (
            title: section.title,
            entries: section.entries.where((entry) {
              final words = _normalize(
                '${section.title} ${entry.title} ${entry.text}',
              ).split(' ');
              return terms.every(
                (term) => words.any((word) => word.startsWith(term)),
              );
            }).toList(),
          ),
    ]..removeWhere((section) => section.entries.isEmpty);

    return SafeArea(
      child: Column(
        children: [
          if (MediaQuery.sizeOf(context).width < 900)
            CompactPageHeader(
              title: 'The founding rules',
              onBack: widget.onBack,
              backTooltip: 'Back to Home',
            ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (MediaQuery.sizeOf(context).width >= 900)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          'The founding rules',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _search,
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        onChanged: (_) => _updateSearch(),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: 'Search rules',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _search.clear();
                                    _updateSearch();
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: sections.isEmpty ? 1 : sections.length,
                        itemBuilder: (context, index) {
                          if (sections.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: const Text(
                                  'No rules match your search.',
                                ),
                              ),
                            );
                          }
                          final section = sections[index];
                          if (searching) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    12,
                                    0,
                                    8,
                                  ),
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      section.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                  ),
                                ),
                                for (final entry in section.entries)
                                  _RuleText(entry: entry),
                              ],
                            );
                          }
                          return ExpansionTile(
                            key: PageStorageKey(section.title),
                            tilePadding: EdgeInsets.zero,
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            title: Text(section.title),
                            children: [
                              for (final entry in section.entries)
                                _RuleText(entry: entry),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleText extends StatelessWidget {
  const _RuleText({required this.entry});

  final RuleEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              entry.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 4),
          Text(entry.text),
        ],
      ),
    );
  }
}
