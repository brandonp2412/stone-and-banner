import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/ai_turn_coordinator.dart';
import 'engine/match.dart';
import 'engine/heuristic_ai.dart';
import 'engine/world_seed.dart';
import 'replay_codes.dart';
import 'ui/match_screen.dart';
import 'ui/game_notice.dart';
import 'ui/resource_icon.dart';
import 'ui/lan_room_page.dart';

MatchEvent? _chooseComputerEvent(MatchState state) =>
    const HeuristicAi().choose(state);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  registerResourceIconLicenses();
  await Future.wait([loadResourceIcons(), restoreResourceIconStyle()]);
  runApp(const StoneBannerApp());
}

enum Page { home, board, rules, setup }

class StoneBannerApp extends StatefulWidget {
  const StoneBannerApp({super.key, this.worldSeedFactory = randomWorldSeed});

  /// Production games get a fresh seed; tests may supply a fixed seed.
  final int Function() worldSeedFactory;

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
  int aiOpponentCount = 2; // Solo play by default when Vs AI is chosen.

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
        aiSeats.contains(AiTurnCoordinator.actingSeat(s, aiSeats.contains));
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
      // Give each committed computer action room for its on-screen animation.
      delay: const Duration(milliseconds: 950),
      decide: (state) => compute(_chooseComputerEvent, state),
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
        // Do not interrupt navigation if storage finishes loading late.
        if (replay != null && page == Page.home) resume();
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
  final names = [
    for (var i = 1; i <= 4; i++) TextEditingController(text: 'Player $i'),
  ];

  @override
  void dispose() {
    ai.pause();
    WidgetsBinding.instance.removeObserver(this);
    for (final n in names) {
      n.dispose();
    }
    super.dispose();
  }

  void fail(String text) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(GameNotice.snackBar(text, error: true));
  }

  Future<void> confirmStart(BuildContext dialogContext) async {
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
      ], widget.worldSeedFactory());
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
    } on StateError catch (e) {
      fail(e.message);
    }
  }

  Future<void> _showMatchActions(BuildContext parentContext) async {
    ai.pause();
    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) => Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: const Text('Actions'),
                onTap: () => Navigator.pop(dialogContext),
              ),
              for (final entry in [
                ('Rules', Page.rules, Icons.menu_book),
                ('Home', Page.home, Icons.home_outlined),
              ])
                ListTile(
                  leading: Icon(entry.$3),
                  title: Text(entry.$1),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    setState(() => page = entry.$2);
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _syncAi();
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

  Widget _setupContent(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final options = ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Match setup', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Choose who plays. All opponents run locally.',
            style: TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Game options',
            style: TextStyle(
              color: Color(0xffefd6a3),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Hot-seat'),
                selected: !computerOpponents,
                onSelected: (_) => setState(() => computerOpponents = false),
              ),
              ChoiceChip(
                label: const Text('Vs AI'),
                selected: computerOpponents,
                onSelected: (_) => setState(() => computerOpponents = true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final count in [3, 4])
                ChoiceChip(
                  label: Text('$count players'),
                  selected: seats == count,
                  onSelected: (_) => setState(() {
                    seats = count;
                    if (aiOpponentCount >= seats) aiOpponentCount = seats - 1;
                  }),
                ),
            ],
          ),
        ],
      );
      final players = Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                Text(
                  computerOpponents ? 'Computer opponents' : 'Your table',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (computerOpponents) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (var i = 1; i < seats; i++)
                        ChoiceChip(
                          label: Text('$i AI'),
                          selected: aiOpponentCount == i,
                          onSelected: (_) =>
                              setState(() => aiOpponentCount = i),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  computerOpponents
                      ? '$humanSeats ${humanSeats == 1 ? 'human' : 'humans'} · $aiOpponentCount ${aiOpponentCount == 1 ? 'computer' : 'computers'}'
                      : '$seats humans · pass the device between turns',
                  style: const TextStyle(
                    color: Color(0xffabbfc2),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Player names',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text('Choose names for human players'),
                const SizedBox(height: 16),
                for (var i = 0; i < humanSeats; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: names[i],
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Player ${i + 1}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (savedReplay != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Replaces your saved match',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: () => confirmStart(context),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    savedReplay == null ? 'Start match' : 'Start new match',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      return Material(
        key: const ValueKey('stone-setup-page'),
        color: const Color(0xff101e25),
        child: SafeArea(
          child: bounds.maxWidth >= 600
              ? Row(
                  children: [
                    Expanded(child: options),
                    const VerticalDivider(width: 1),
                    Expanded(child: players),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: options),
                    Expanded(child: players),
                  ],
                ),
        ),
      );
    },
  );

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
      themeMode: ThemeMode.dark,
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
              appBar: page == Page.board
                  ? null
                  : AppBar(
                      toolbarHeight: 48,
                      centerTitle: false,
                      leading: page == Page.home
                          ? const Icon(Icons.flag_outlined)
                          : IconButton(
                              tooltip: 'Back to Home',
                              onPressed: () {
                                ai.pause();
                                setState(() => page = Page.home);
                              },
                              icon: const Icon(Icons.arrow_back),
                            ),
                      title: const Text(
                        'STONE & BANNER',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ),
              body: Stack(
                fit: StackFit.expand,
                children: [
                  switch (page) {
                    Page.home => _LandingHall(
                      onNew: () => setState(() => page = Page.setup),
                      onContinue: savedReplay == null ? null : resume,
                      onRules: () => setState(() => page = Page.rules),
                      onImport: () => importMatch(context),
                      onLan: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LanRoomPage(),
                        ),
                      ),
                    ),
                    Page.setup => LayoutBuilder(
                      builder: (context, bounds) => bounds.maxWidth >= 1200
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(48),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1100,
                                    maxHeight: 640,
                                  ),
                                  child: _setupContent(context),
                                ),
                              ),
                            )
                          : _setupContent(context),
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
                          : handoff
                          ? const SizedBox.expand()
                          : MatchView(
                              state: current,
                              onEvent: dispatch,
                              onHome: () {
                                ai.pause();
                                setState(() => page = Page.home);
                              },
                              onRules: () {
                                ai.pause();
                                setState(() => page = Page.rules);
                              },
                              computerSeats: aiSeats,
                              visibleSeat: oneHumanMatch ? 0 : current.active,
                              observing: aiActing,
                              automationError: aiError,
                              onResumeAutomation: () {
                                setState(() => aiError = null);
                                _syncAi();
                              },
                            ),
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'Advanced play',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'Glossary',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
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
                  if (page == Page.board && handoff && current != null)
                    Positioned.fill(
                      child: Material(
                        color: const Color(0xff101e25),
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.lock_outline,
                                            size: 44,
                                            color: Color(0xffe5c183),
                                          ),
                                          const SizedBox(width: 20),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Pass the device',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headlineSmall,
                                                ),
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
                                              ],
                                            ),
                                          ),
                                        ],
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
                                      Builder(
                                        builder: (context) => TextButton.icon(
                                          onPressed: () =>
                                              _showMatchActions(context),
                                          icon: const Icon(
                                            Icons.layers_outlined,
                                          ),
                                          label: const Text('Actions'),
                                        ),
                                      ),
                                    ],
                                  ),
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
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    content: TextField(
      controller: controller,
      minLines: 1,
      maxLines: 3,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
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

class _LandingHall extends StatelessWidget {
  const _LandingHall({
    required this.onNew,
    required this.onContinue,
    required this.onRules,
    required this.onImport,
    required this.onLan,
  });
  final VoidCallback onNew, onRules, onImport, onLan;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compactLandscape =
          box.maxWidth > box.maxHeight && box.maxHeight < 560;
      final artwork = Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/art/stone_banner_crest.jpg',
            fit: BoxFit.cover,
            semanticLabel: 'Original Stone & Banner emblem: a standing stone and gold banner',
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00101e25), Color(0xee101e25)],
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A REALM OF YOUR OWN',
                  style: TextStyle(
                    color: Color(0xffefd6a3),
                    fontSize: 11,
                    letterSpacing: 2.5,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Raise a town.\nShape a realm.',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xfffff0d0),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final menu = Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: compactLandscape ? 16 : 24,
            vertical: compactLandscape ? 8 : 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Stone & Banner',
                  style: TextStyle(
                    fontSize: compactLandscape ? 23 : 27,
                    fontWeight: FontWeight.w700,
                    color: Color(0xffefd6a3),
                  ),
                ),
                SizedBox(height: compactLandscape ? 4 : 8),
                const Text(
                  'Build, trade and defend your way to 15 Victory Points.',
                  style: TextStyle(color: Color(0xffabbfc2), fontSize: 13),
                ),
                SizedBox(height: compactLandscape ? 10 : 20),
                if (onContinue != null) ...[
                  FilledButton.icon(
                    onPressed: onContinue,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Continue saved match'),
                  ),
                  SizedBox(height: compactLandscape ? 4 : 8),
                ],
                FilledButton.tonalIcon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add),
                  label: const Text('New local match'),
                ),
                SizedBox(height: compactLandscape ? 4 : 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  children: [
                    TextButton.icon(
                      onPressed: onRules,
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('Learn the rules'),
                    ),
                    TextButton.icon(
                      onPressed: onLan,
                      icon: const Icon(Icons.groups_outlined, size: 18),
                      label: const Text('LAN multiplayer'),
                    ),
                    TextButton.icon(
                      onPressed: onImport,
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('Import replay'),
                    ),
                  ],
                ),
                if (!compactLandscape) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'OFFLINE PLAY  ·  LOCAL AI  ·  3–4 SEATS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.3,
                      color: Color(0xff8fa9ac),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      final desktop = box.maxWidth >= 1200 && box.maxHeight >= 650;
      return Material(
        key: const ValueKey('stone-home-page'),
        color: const Color(0xff101e25),
        child: SafeArea(
          child: desktop
              ? Padding(
                  padding: const EdgeInsets.all(48),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: artwork,
                        ),
                      ),
                      const SizedBox(width: 48),
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'WELCOME TO THE TABLE',
                                style: TextStyle(
                                  color: Color(0xff8fa9ac),
                                  letterSpacing: 2,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(child: menu),
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Row(
                                children: [
                                  Icon(Icons.save_outlined, size: 20),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Your match saves automatically on this device.',
                                      style: TextStyle(
                                        color: Color(0xffabbfc2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : box.maxWidth > box.maxHeight
              ? Row(
                  children: [
                    Expanded(flex: 5, child: artwork),
                    Expanded(flex: 6, child: menu),
                  ],
                )
              : menu,
        ),
      );
    },
  );
}
