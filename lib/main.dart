import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/ai_turn_coordinator.dart';
import 'engine/match.dart';
import 'replay_codes.dart';
import 'ui/match_screen.dart';
import 'ui/lan_room_page.dart';

void main() => runApp(const StoneBannerApp());

enum Page { home, board, rules, setup }

class StoneBannerApp extends StatefulWidget {
  const StoneBannerApp({super.key});
  @override
  State<StoneBannerApp> createState() => _StoneBannerAppState();
}

class _StoneBannerAppState extends State<StoneBannerApp>
    with WidgetsBindingObserver {
  static const _savedMatchKey = 'stone_banner_local_replay_v1';
  static const _savedSessionKey = 'stone_banner_local_session_v2';
  late final AiTurnCoordinator ai;
  Set<int> aiSeats = <int>{};
  Set<int> savedAiSeats = <int>{};
  bool computerOpponents = false;
  int aiOpponentCount = 1;

  int get humanSeats => seats - (computerOpponents ? aiOpponentCount : 0);
  bool get soloHumanVsAi => computerOpponents && humanSeats == 1;
  bool get oneHumanMatch =>
      match != null &&
      aiSeats.isNotEmpty &&
      match!.players.length - aiSeats.length == 1;
  bool _foreground = true;
  int aiMoveCount = 0;
  String? aiError;

  bool get aiActing {
    final s = match;
    return s != null &&
        s.phase != MatchPhase.finished &&
        aiSeats.contains(s.tactical?.responder ?? s.active);
  }

  void _syncAi() {
    if (mounted &&
        _foreground &&
        page == Page.board &&
        !handoff &&
        aiError == null &&
        aiActing) {
      ai.resume();
    } else {
      ai.pause();
    }
  }

  bool _commitAi(MatchState expected, MatchState next) {
    if (!mounted ||
        !_foreground ||
        page != Page.board ||
        handoff ||
        !identical(match, expected) ||
        !aiActing) {
      return false;
    }
    final oldOwner = expected.tactical?.responder ?? expected.active;
    final nextOwner = next.tactical?.responder ?? next.active;
    setState(() {
      match = next;
      aiMoveCount++;
      handoff =
          oldOwner != nextOwner &&
          !aiSeats.contains(nextOwner) &&
          !oneHumanMatch;
    });
    _save(next);
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncAi();
  }

  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  String? savedReplay;
  Future<void> _saveTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ai = AiTurnCoordinator(
      read: () => match,
      commit: _commitAi,
      isComputerSeat: (seat) => aiSeats.contains(seat),
      onError: (error) {
        if (mounted) setState(() => aiError = error.toString());
      },
    );
    unawaited(_loadSaved());
  }

  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var replay = prefs.getString(_savedMatchKey);
      var seats = <int>{};
      final session = prefs.getString(_savedSessionKey);
      if (session != null) {
        try {
          final data = jsonDecode(session) as Map<String, dynamic>;
          final encoded = data['replay'];
          final ids = data['computerSeats'];
          if (data['version'] == 2 &&
              encoded is String &&
              ids is List &&
              ids.every((id) => id is int && id >= 0)) {
            replay = encoded;
            seats = ids.cast<int>().toSet();
          }
        } on Object {
          // Legacy replay remains available if this metadata was damaged.
        }
      }
      if (mounted && match == null) {
        setState(() {
          savedReplay = replay;
          savedAiSeats = seats;
        });
      }
    } on Object {
      if (mounted) fail('Could not load the saved local match.');
    }
  }

  void _save(MatchState state) {
    final replay = MatchEngine.exportReplay(state);
    savedReplay = replay;
    savedAiSeats = {...aiSeats};
    final session = jsonEncode({
      'version': 2,
      'replay': replay,
      'computerSeats': (aiSeats.toList()..sort()),
    });
    // Serialize writes: a slower prior event must never replace a newer replay.
    _saveTail = _saveTail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(_savedSessionKey, session) ||
            !await prefs.setString(_savedMatchKey, replay)) {
          throw StateError('Storage rejected the replay.');
        }
      } on Object {
        if (mounted) {
          fail('Autosave failed. Copy the replay to preserve this match.');
        }
      }
    });
  }

  void resume() {
    final replay = savedReplay;
    if (replay == null) return;
    try {
      final loaded = MatchEngine.importReplay(replay);
      ai.pause();
      setState(() {
        match = loaded;
        aiSeats = savedAiSeats
            .where((s) => s > 0 && s < loaded.players.length)
            .toSet();
        aiMoveCount = 0;
        aiError = null;
        page = Page.board;
        handoff =
            !aiSeats.contains(loaded.tactical?.responder ?? loaded.active) &&
            !(aiSeats.length == loaded.players.length - 1);
      });
      _syncAi();
    } on Object {
      fail('Saved replay is invalid. Try importing a backup code.');
    }
  }

  Page page = Page.home;
  MatchState? match;
  bool handoff = false;
  int seats = 3;
  final seed = TextEditingController(text: '20261027');
  final names = [
    for (var i = 1; i <= 4; i++) TextEditingController(text: 'Player $i'),
  ];

  @override
  void dispose() {
    ai.pause();
    WidgetsBinding.instance.removeObserver(this);
    seed.dispose();
    for (final n in names) {
      n.dispose();
    }
    super.dispose();
  }

  void fail(String text) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> confirmStart(BuildContext dialogContext) async {
    if (int.tryParse(seed.text.trim()) == null) {
      fail('Enter a numeric world seed.');
      return;
    }
    final humanNames = [
      for (var i = 0; i < humanSeats; i++) names[i].text.trim(),
    ];
    if (humanNames.any((name) => name.isEmpty)) {
      fail('Enter a name for each human player.');
      return;
    }
    if (humanNames.map((name) => name.toLowerCase()).toSet().length !=
        humanNames.length) {
      fail('Give each human player a different name.');
      return;
    }
    if (savedReplay != null) {
      final replace = await showDialog<bool>(
        context: dialogContext,
        builder: (context) => AlertDialog(
          title: const Text('Replace saved match?'),
          content: const Text(
            'Starting a new match replaces the match stored on this device. '
            'Copy its replay first if you want to keep it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep saved match'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start new match'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true) return;
    }
    start();
  }

  void start() {
    try {
      final firstComputer = humanSeats;
      final s = MatchEngine.newGame([
        for (var i = 0; i < seats; i++)
          i >= firstComputer
              ? 'Computer ${i - firstComputer + 1}'
              : names[i].text.trim(),
      ], int.parse(seed.text));
      ai.pause();
      setState(() {
        match = s;
        aiSeats = computerOpponents
            ? {for (var i = firstComputer; i < seats; i++) i}
            : <int>{};
        aiMoveCount = 0;
        aiError = null;
        page = Page.board;
        handoff = !soloHumanVsAi;
      });
      _save(s);
      _syncAi();
    } on FormatException {
      fail('Enter a numeric seed.');
    } on StateError catch (e) {
      fail(e.message);
    }
  }

  void dispatch(MatchEvent event) {
    if (page != Page.board || handoff || aiActing || match == null) return;
    try {
      final previous = match!;
      final s = MatchEngine.apply(previous, event);
      final oldOwner = previous.tactical?.responder ?? previous.active;
      final nextOwner = s.tactical?.responder ?? s.active;
      setState(() {
        handoff =
            oldOwner != nextOwner &&
            !aiSeats.contains(nextOwner) &&
            !oneHumanMatch;
        match = s;
      });
      _save(s);
      _syncAi();
    } on StateError catch (e) {
      fail(e.message);
    }
  }

  Future<void> importMatch(BuildContext dialogContext) async {
    final raw = await showDialog<String>(
      context: dialogContext,
      builder: (context) => const _ReplayImportDialog(),
    );
    if (raw == null || !mounted || !dialogContext.mounted) return;
    try {
      final loaded = MatchEngine.importReplay(ReplayCodes.expand(raw));
      if (savedReplay != null) {
        final replace = await showDialog<bool>(
          context: dialogContext,
          builder: (context) => AlertDialog(
            title: const Text('Replace saved match?'),
            content: const Text(
              'Importing replaces the match saved on this device. '
              'Copy its replay first if you want to keep it. '
              'Imported replays continue in hot-seat mode; computer seats are not included in share codes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep saved match'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Import and replace'),
              ),
            ],
          ),
        );
        if (!mounted || replace != true) return;
      }
      ai.pause();
      setState(() {
        match = loaded;
        aiSeats = <int>{};
        aiMoveCount = 0;
        aiError = null;
        page = Page.board;
        handoff = true;
      });
      _save(loaded);
    } on Object {
      // A code may contain private hands. Never echo it in a visible error.
      fail('Invalid replay code. Check the text and try again.');
    }
  }

  bool _needsWrappedChoices(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360 ||
      MediaQuery.textScalerOf(context).scale(1) > 1.35;

  @override
  Widget build(BuildContext context) {
    final current = match;
    return MaterialApp(
      title: 'Stone & Banner',
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSans',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff806334)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffe7bf7b),
          brightness: Brightness.dark,
          surface: const Color(0xff192529),
        ),
      ),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) => PopScope(
          canPop: page == Page.home,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              ai.pause();
              setState(() => page = Page.home);
            }
          },
          child: Focus(
            autofocus: true,
            skipTraversal: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape &&
                  (page != Page.home || Navigator.of(context).canPop())) {
                Navigator.of(context).maybePop();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              appBar: AppBar(
                centerTitle: true,
                title: const Text(
                  'STONE & BANNER',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.7,
                  ),
                ),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: page == Page.setup ? 0 : page.index,
                onDestinationSelected: (n) {
                  ai.pause();
                  setState(() {
                    final next = Page.values[n];
                    // Human private hands require consent after every re-entry.
                    if (next == Page.board &&
                        page != Page.board &&
                        match != null) {
                      handoff = !aiActing && !oneHumanMatch;
                    }
                    page = next;
                  });
                  _syncAi();
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.hexagon_outlined),
                    label: 'Board',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    label: 'Rules',
                  ),
                ],
              ),
              body: Stack(
                children: [
                  switch (page) {
                    Page.home => Center(
                      key: const ValueKey('stone-home-page'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Image.asset(
                                    'assets/art/stone_banner_crest.jpg',
                                    width: 88,
                                    height: 88,
                                    fit: BoxFit.cover,
                                    semanticLabel: 'Original Stone & Banner emblem: a standing stone and gold banner',
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Stone & Banner',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Raise a town. Shape a realm.',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (savedReplay != null) ...[
                              FilledButton.tonalIcon(
                                onPressed: resume,
                                icon: const Icon(Icons.restore),
                                label: const Text('Continue saved match'),
                              ),
                              const SizedBox(height: 10),
                            ],
                            FilledButton.icon(
                              onPressed: () =>
                                  setState(() => page = Page.setup),
                              icon: const Icon(Icons.add),
                              label: const Text('New local match'),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Build a realm together, or challenge offline computer opponents. First to 15 Victory Points wins.',
                            ),
                            const SizedBox(height: 20),
                            Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                      Icons.menu_book_outlined,
                                    ),
                                    title: const Text('Learn the rules'),
                                    subtitle: const Text(
                                      'A quick guide and glossary',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () =>
                                        setState(() => page = Page.rules),
                                  ),
                                  const Divider(height: 1),
                                  ListTile(
                                    leading: const Icon(Icons.groups_outlined),
                                    title: const Text('LAN multiplayer'),
                                    subtitle: const Text(
                                      'Connect on a trusted local network',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const LanRoomPage(),
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  ListTile(
                                    leading: const Icon(Icons.history),
                                    title: const Text('Import replay'),
                                    subtitle: const Text(
                                      'Restore a shared match code',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => importMatch(context),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '3–4 seats · Offline first · Deterministic replay',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Page.setup => Center(
                      key: const ValueKey('stone-setup-page'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Back to Home',
                                  onPressed: () =>
                                      setState(() => page = Page.home),
                                  icon: const Icon(Icons.arrow_back),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Match setup',
                                    softWrap: true,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Choose who plays. All opponents run locally.',
                            ),
                            const SizedBox(height: 16),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  12,
                                  18,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Game options',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    const SizedBox(height: 16),
                                    if (_needsWrappedChoices(context))
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          ChoiceChip(
                                            label: const Text('Hot-seat'),
                                            selected: !computerOpponents,
                                            onSelected: (_) => setState(
                                              () => computerOpponents = false,
                                            ),
                                          ),
                                          ChoiceChip(
                                            label: const Text('Vs AI'),
                                            selected: computerOpponents,
                                            onSelected: (_) => setState(
                                              () => computerOpponents = true,
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      SegmentedButton<bool>(
                                        segments: const [
                                          ButtonSegment(
                                            value: false,
                                            icon: Icon(Icons.groups_outlined),
                                            label: Text('Hot-seat'),
                                          ),
                                          ButtonSegment(
                                            value: true,
                                            icon: Icon(
                                              Icons.smart_toy_outlined,
                                            ),
                                            label: Text('Vs AI'),
                                          ),
                                        ],
                                        selected: {computerOpponents},
                                        onSelectionChanged: (value) => setState(
                                          () => computerOpponents = value.first,
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    if (_needsWrappedChoices(context))
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          for (final count in [3, 4])
                                            ChoiceChip(
                                              label: Text('$count players'),
                                              selected: seats == count,
                                              onSelected: (_) => setState(() {
                                                seats = count;
                                                if (aiOpponentCount >= seats) {
                                                  aiOpponentCount = seats - 1;
                                                }
                                              }),
                                            ),
                                        ],
                                      )
                                    else
                                      SegmentedButton<int>(
                                        segments: const [
                                          ButtonSegment(
                                            value: 3,
                                            label: Text('3 players'),
                                          ),
                                          ButtonSegment(
                                            value: 4,
                                            label: Text('4 players'),
                                          ),
                                        ],
                                        selected: {seats},
                                        onSelectionChanged: (v) => setState(() {
                                          seats = v.first;
                                          if (aiOpponentCount >= seats) {
                                            aiOpponentCount = seats - 1;
                                          }
                                        }),
                                      ),
                                    if (computerOpponents) ...[
                                      const SizedBox(height: 16),
                                      Text(
                                        'Computer opponents',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      const SizedBox(height: 8),
                                      if (_needsWrappedChoices(context))
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (var i = 1; i < seats; i++)
                                              ChoiceChip(
                                                label: Text('$i AI'),
                                                selected: aiOpponentCount == i,
                                                onSelected: (_) => setState(
                                                  () => aiOpponentCount = i,
                                                ),
                                              ),
                                          ],
                                        )
                                      else
                                        SegmentedButton<int>(
                                          segments: [
                                            for (var i = 1; i < seats; i++)
                                              ButtonSegment(
                                                value: i,
                                                label: Text('$i AI'),
                                              ),
                                          ],
                                          selected: {aiOpponentCount},
                                          onSelectionChanged: (value) =>
                                              setState(
                                                () => aiOpponentCount =
                                                    value.first,
                                              ),
                                        ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '$humanSeats human${humanSeats == 1 ? '' : 's'} · $aiOpponentCount computer · seeded offline strategy',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: () => confirmStart(context),
                                      icon: const Icon(Icons.play_arrow),
                                      label: Text(
                                        savedReplay == null
                                            ? 'Start match'
                                            : 'Start new match',
                                      ),
                                    ),
                                    if (savedReplay != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'Replaces your saved match',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    ExpansionTile(
                                      title: const Text('Player names'),
                                      subtitle: Text(
                                        computerOpponents
                                            ? 'Edit ${humanSeats == 1 ? 'your name' : 'human names'}'
                                            : 'Defaults: Player 1–$seats',
                                      ),
                                      tilePadding: EdgeInsets.zero,
                                      children: [
                                        for (
                                          var i = 0;
                                          i < humanSeats;
                                          i++
                                        ) ...[
                                          TextField(
                                            controller: names[i],
                                            textCapitalization:
                                                TextCapitalization.words,
                                            decoration: InputDecoration(
                                              labelText: 'Player ${i + 1}',
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                        TextField(
                                          controller: seed,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText: 'World seed',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Page.board =>
                      current == null
                          ? Center(
                              child: FilledButton(
                                onPressed: () =>
                                    setState(() => page = Page.setup),
                                child: const Text('Create a match'),
                              ),
                            )
                          : handoff || aiActing
                          ? const SizedBox.expand()
                          : MatchView(state: current, onEvent: dispatch),
                    Page.rules => Center(
                      key: const ValueKey('stone-rules-page'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            Text(
                              'The founding rules',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'The essentials',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            const _Rule(
                              '1 · Claim',
                              'Each seat places two free Village and Road pairs in a snake draft. Leave a gap between settlements.',
                            ),
                            const _Rule(
                              '2 · Roll',
                              'Roll numbered dice to earn goods from neighbouring terrain. A seven moves the Bandit.',
                            ),
                            const _Rule(
                              '3 · Build and trade',
                              'Spend goods to extend roads, found Villages and upgrade to Towns or Capitals. Exchange with the bank or offer a rival trade.',
                            ),
                            const _Rule(
                              '4 · Win',
                              'First to 15 Victory Points wins. Village = 1, Town = 2, Capital = 4; the longest road of at least five sides earns 2.',
                            ),
                            const Divider(height: 24),
                            ExpansionTile(
                              title: const Text('Advanced play'),
                              subtitle: const Text(
                                'Knights, cards, seasons and reactions',
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                0,
                              ),
                              children: const [
                                _Rule(
                                  'Town Developments',
                                  'Innovation, Commerce and Governance have five tiers each. Developed Towns can produce paper, cloth and coin.',
                                ),
                                _Rule(
                                  'Reaver Fleet and Knights',
                                  'Activate and promote Knights to defend the realm. Fortifications shelter Towns when an Invasion succeeds.',
                                ),
                                _Rule(
                                  'Reactions',
                                  'Eligible seats can intercept theft, counter Governance cards or pledge Invasion aid. Pass is always available.',
                                ),
                                _Rule(
                                  'Catch-up',
                                  'Seats behind by three points may exchange 3:1 with the bank once a round; drought relief is bounded.',
                                ),
                              ],
                            ),
                            ExpansionTile(
                              title: const Text('Glossary'),
                              subtitle: const Text(
                                'Goods, structures and turn terms',
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                0,
                              ),
                              children: const [
                                _Rule(
                                  'Basic goods',
                                  'Wood, brick, wheat, wool and ore pay for roads, structures and Knights.',
                                ),
                                _Rule(
                                  'Commodities',
                                  'Paper, cloth and coin come from developed Towns and help build Capitals.',
                                ),
                                _Rule(
                                  'Victory Points (VP)',
                                  'A seat’s score. Reach 15 points to win; Charter Points and Guardian’s Honour also count.',
                                ),
                                _Rule(
                                  'Bandit',
                                  'A seven relocates the Bandit and may cause discards or theft.',
                                ),
                                _Rule(
                                  'Seed and replay',
                                  'The saved world seed and all accepted events reproduce a match exactly.',
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Every move is engine-validated and logged for deterministic replay.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  },
                  if (page == Page.board && aiActing && current != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Card(
                              margin: const EdgeInsets.all(24),
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.smart_toy_outlined,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      aiError == null
                                          ? 'Computer turn'
                                          : 'Computer paused',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      current
                                          .players[current
                                                  .tactical
                                                  ?.responder ??
                                              current.active]
                                          .id,
                                    ),
                                    const SizedBox(height: 12),
                                    if (aiError == null) ...[
                                      const LinearProgressIndicator(),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Move $aiMoveCount · preparing next action',
                                      ),
                                    ] else ...[
                                      Text(
                                        aiError!,
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      FilledButton(
                                        onPressed: () {
                                          setState(() => aiError = null);
                                          _syncAi();
                                        },
                                        child: const Text('Resume computer'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (page == Page.board && handoff && current != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Card(
                              margin: const EdgeInsets.all(24),
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.lock_outline, size: 42),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Pass the device',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      current
                                          .players[current
                                                  .tactical
                                                  ?.responder ??
                                              current.active]
                                          .id,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    Text(
                                      current.tactical == null
                                          ? 'Your turn'
                                          : 'Private tactical response',
                                    ),
                                    const SizedBox(height: 20),
                                    FilledButton.icon(
                                      onPressed: () {
                                        setState(() => handoff = false);
                                        _syncAi();
                                      },
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                      ),
                                      label: const Text("I'm ready"),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Owns the controller until the dialog's exit animation has finished.
class _ReplayImportDialog extends StatefulWidget {
  const _ReplayImportDialog();

  @override
  State<_ReplayImportDialog> createState() => _ReplayImportDialogState();
}

class _ReplayImportDialogState extends State<_ReplayImportDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import replay'),
    content: TextField(
      controller: controller,
      maxLines: 5,
      decoration: const InputDecoration(
        labelText: 'Paste replay JSON',
        helperText: 'Compact share codes also work',
        border: OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Load'),
      ),
    ],
  );
}

class _Rule extends StatelessWidget {
  const _Rule(this.name, this.description);
  final String name, description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(description),
      ],
    ),
  );
}
