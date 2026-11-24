import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ui/compact_layout.dart';

import 'package:flutter/material.dart';

import 'ui/game_colors.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/ai_turn_coordinator.dart';
import 'engine/match.dart';
import 'engine/heuristic_ai.dart';
import 'engine/world_seed.dart';
import 'match_archive.dart';
import 'ui/match_history.dart';
import 'replay_codes.dart';
import 'ui/match_screen.dart';
import 'ui/game_notice.dart';
import 'ui/resource_icon.dart';
import 'ui/p2p_room_page.dart';
import 'network/p2p_transport.dart';

MatchEvent? _chooseComputerEvent((MatchState, BotDifficulty) input) =>
    HeuristicAi(difficulty: input.$2).choose(input.$1);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Follow the device's orientation, including portrait on phones.
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  registerResourceIconLicenses();
  await Future.wait([loadResourceIcons(), restoreResourceIconStyle()]);
  runApp(const StoneBannerApp());
}

enum Page { home, board, rules, setup }

class StoneBannerApp extends StatefulWidget {
  const StoneBannerApp({
    super.key,
    this.worldSeedFactory = randomWorldSeed,
    this.randomizeTurnOrder = true,
  });

  /// Production games get a fresh seed; tests may supply a fixed seed.
  final int Function() worldSeedFactory;

  /// Disable for deterministic widget fixtures; live games randomize seats.
  final bool randomizeTurnOrder;

  @override
  State<StoneBannerApp> createState() => _StoneBannerAppState();
}

class _StoneBannerAppState extends State<StoneBannerApp>
    with WidgetsBindingObserver {
  bool _dismissedInitialP2pLink = false;
  static const _setupKey = 'stone_banner_setup_v1';
  bool _setupEdited = false;
  bool _restoringSetup = false;
  static const _savedMatchKey = 'stone_banner_local_replay_v1';
  static const _savedSessionKey = 'stone_banner_local_session_v2';
  late final AiTurnCoordinator ai;
  Set<int> aiSeats = <int>{};
  Set<int> savedAiSeats = <int>{};
  BotDifficulty botDifficulty = BotDifficulty.hard;
  BotDifficulty matchBotDifficulty = BotDifficulty.hard;
  BotDifficulty savedBotDifficulty = BotDifficulty.hard;
  bool computerOpponents = false;
  int aiOpponentCount = 2; // Solo play by default when Vs bots is chosen.

  int get humanSeats => seats - (computerOpponents ? aiOpponentCount : 0);
  bool get soloHumanVsAi => computerOpponents && humanSeats == 1;
  bool get oneHumanMatch =>
      match != null &&
      aiSeats.isNotEmpty &&
      match!.players.length - aiSeats.length == 1;
  bool _foreground = true;
  bool pauseInBackground = true;
  ThemeMode themeMode = ThemeMode.dark;
  double aiDelaySeconds = 2.4;
  bool get _canRun => _foreground || !pauseInBackground;
  int aiMoveCount = 0;
  String? aiError;
  Timer? _aiRecoveryTimer;
  Timer? _localTradeGraceTimer;
  int? _localTradeOfferId;
  int? _localTradeExpiredId;
  bool _fastForwardingBots = false;
  int _localAiFailedVersion = -1;
  int _localAiFailures = 0;

  bool _waitingOnLocalTrade(MatchState state) {
    final offer =
        state.phase == MatchPhase.actions &&
            state.tactical == null &&
            aiSeats.contains(state.active)
        ? state.offers
              .where(
                (o) =>
                    o.proposer == state.active &&
                    List.generate(state.players.length, (seat) => seat).any(
                      (seat) => !aiSeats.contains(seat) && o.canRespond(seat),
                    ),
              )
              .firstOrNull
        : null;
    if (offer == null || _fastForwardingBots) {
      _localTradeGraceTimer?.cancel();
      _localTradeGraceTimer = null;
      _localTradeOfferId = null;
      return false;
    }
    if (_localTradeExpiredId == offer.id) return false;
    if (_localTradeOfferId != offer.id) {
      _localTradeGraceTimer?.cancel();
      _localTradeOfferId = offer.id;
      _localTradeGraceTimer = Timer(const Duration(seconds: 30), () {
        if (!mounted) return;
        _localTradeExpiredId = offer.id;
        _syncAi();
      });
    }
    return true;
  }

  void _onLocalAiFailure(Object error) {
    if (!mounted) return;
    final state = match;
    if (state == null) return;
    if (_localAiFailedVersion != state.events.length) {
      _localAiFailedVersion = state.events.length;
      _localAiFailures = 0;
    }
    _localAiFailures++;
    setState(() => aiError = '$error');
    _aiRecoveryTimer?.cancel();
    _aiRecoveryTimer = Timer(const Duration(milliseconds: 400), () {
      _aiRecoveryTimer = null;
      if (!mounted || match == null || page != Page.board) return;
      final current = match!;
      final seat = AiTurnCoordinator.actingSeat(current, aiSeats.contains);
      if (!aiSeats.contains(seat)) return;
      if (_localAiFailures < 3) {
        setState(() => aiError = null);
        _syncAi();
        return;
      }
      final offer = seat != current.actingSeat
          ? current.offers
                .where(
                  (o) => o.proposer == current.active && o.canRespond(seat),
                )
                .firstOrNull
          : null;
      final fallback = offer != null
          ? RespondTrade(seat, false, offerId: offer.id)
          : MatchEngine.idleEvent(current);
      if (fallback == null) return;
      try {
        final next = MatchEngine.apply(current, fallback);
        setState(() => aiError = null);
        if (_commitAi(current, next)) _localAiFailures = 0;
      } on Object {
        // Preserve state if even the authoritative idle action is rejected.
      }
    });
  }

  bool get aiActing {
    final s = match;
    return s != null &&
        s.phase != MatchPhase.finished &&
        aiSeats.contains(AiTurnCoordinator.actingSeat(s, aiSeats.contains));
  }

  void _fastForwardBots() {
    if (!aiActing) return;
    setState(() => _fastForwardingBots = true);
    _syncAi();
    ai.fastForward();
  }

  void _syncAi() {
    if (!aiActing || page != Page.board) _fastForwardingBots = false;
    if (mounted &&
        _canRun &&
        page == Page.board &&
        !handoff &&
        aiError == null &&
        aiActing &&
        !_waitingOnLocalTrade(match!)) {
      ai.resume();
    } else {
      ai.pause();
    }
  }

  bool _commitAi(MatchState expected, MatchState next) {
    if (!mounted ||
        !_canRun ||
        page != Page.board ||
        handoff ||
        !identical(match, expected) ||
        !aiActing) {
      return false;
    }
    final oldOwner = expected.actingSeat;
    final nextOwner = next.actingSeat;
    final rollAfterSkip =
        _fastForwardingBots &&
        oneHumanMatch &&
        next.phase == MatchPhase.roll &&
        next.tactical == null &&
        !aiSeats.contains(nextOwner);
    setState(() {
      match = next;
      aiMoveCount++;
      handoff =
          oldOwner != nextOwner &&
          !aiSeats.contains(nextOwner) &&
          !oneHumanMatch;
    });
    _save(next, previous: expected);
    _syncAi();
    if (rollAfterSkip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_canRun ||
            page != Page.board ||
            handoff ||
            !identical(match, next)) {
          return;
        }
        final (a, b) = MatchEngine.expectedDice(next);
        dispatch(RollDice(a, b));
      });
    }
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
      delay: const Duration(milliseconds: 2400),
      decide: (state) =>
          compute(_chooseComputerEvent, (state, matchBotDifficulty)),
      onError: _onLocalAiFailure,
    );
    for (final name in names) {
      name.addListener(_saveSetup);
    }
    unawaited(_loadSaved());
  }

  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          themeMode = ThemeMode.values.firstWhere(
            (m) => m.name == prefs.getString("themeMode"),
            orElse: () => ThemeMode.dark,
          );
          pauseInBackground = prefs.getBool("pauseInBackground") ?? true;
          aiDelaySeconds = prefs.getDouble("aiDelaySeconds") ?? 2.4;
          ai.delay = Duration(milliseconds: (aiDelaySeconds * 1000).round());
        });
      }
      if (mounted && !_setupEdited) {
        try {
          final raw = prefs.getString(_setupKey);
          if (raw != null) {
            final data = jsonDecode(raw) as Map<String, dynamic>;
            _restoringSetup = true;
            setState(() {
              if (data['seats'] is int &&
                  data['seats'] >= 3 &&
                  data['seats'] <= 6) {
                seats = data['seats'] as int;
              }
              if (data['computerOpponents'] is bool) {
                computerOpponents = data['computerOpponents'] as bool;
              }
              botDifficulty = BotDifficulty.parse(data['botDifficulty']);
              final count = data['aiOpponentCount'];
              if (count is int && count > 0 && count < seats) {
                aiOpponentCount = count;
              }
              final storedNames = data['names'];
              if (storedNames is List) {
                for (
                  var i = 0;
                  i < names.length && i < storedNames.length;
                  i++
                ) {
                  if (storedNames[i] is String) names[i].text = storedNames[i];
                }
              }
            });
          }
        } on Object {
          // Invalid setup preferences must not prevent match recovery.
        } finally {
          _restoringSetup = false;
        }
      }
      var replay = prefs.getString(_savedMatchKey);
      var restoredAiSeats = <int>{};
      var restoredDifficulty = BotDifficulty.hard;
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
            restoredDifficulty = BotDifficulty.parse(data['botDifficulty']);
            restoredAiSeats = ids.cast<int>().toSet();
          }
        } on Object {
          // Legacy replay remains available if this metadata was damaged.
        }
      }
      if (mounted && match == null) {
        setState(() {
          savedReplay = replay;
          savedAiSeats = restoredAiSeats;
          savedBotDifficulty = restoredDifficulty;
        });
        // Do not interrupt navigation if storage finishes loading late.
        if (replay != null && page == Page.home) resume(automatic: true);
      }
    } on Object {
      if (mounted) fail('Could not load the saved local match.');
    }
  }

  void _updateSetup(VoidCallback update) {
    setState(update);
    _saveSetup();
  }

  void _saveSetup() {
    if (_restoringSetup) return;
    _setupEdited = true;
    final encoded = jsonEncode({
      'names': [for (final name in names) name.text],
      'seats': seats,
      'computerOpponents': computerOpponents,
      'aiOpponentCount': aiOpponentCount,
      'botDifficulty': botDifficulty.name,
    });
    _saveTail = _saveTail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(_setupKey, encoded)) {
          throw StateError('Storage rejected settings.');
        }
      } on Object {
        if (mounted) fail('Could not save game settings.');
      }
    });
  }

  void _save(MatchState state, {MatchState? previous}) {
    final replay = MatchEngine.exportReplay(state);
    savedReplay = replay;
    savedAiSeats = {...aiSeats};
    savedBotDifficulty = matchBotDifficulty;
    final archivedComputerSeats = {...aiSeats};
    final session = jsonEncode({
      'version': 2,
      'replay': replay,
      'computerSeats': (aiSeats.toList()..sort()),
      'botDifficulty': matchBotDifficulty.name,
    });
    // Serialize writes: a slower prior event must never replace a newer replay.
    _saveTail = _saveTail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(_savedSessionKey, session) ||
            !await prefs.setString(_savedMatchKey, replay)) {
          throw StateError('Storage rejected the replay.');
        }
        if (kDebugMode && previous != null) {
          await DebugMatchLog.append(prefs, previous, state);
        }
        if (state.phase == MatchPhase.finished) {
          await MatchArchive.save(
            prefs,
            state,
            replay: replay,
            computerSeats: archivedComputerSeats,
          );
        }
      } on Object {
        if (mounted) {
          fail('Autosave failed. Copy the replay to preserve this match.');
        }
      }
    });
  }

  // Preserve replaced matches before their autosaves are overwritten.
  void _archiveReplacedMatch() {
    final prior = match;
    final replay = savedReplay;
    final archivedComputerSeats = {...(prior == null ? savedAiSeats : aiSeats)};
    if (prior == null && replay == null) return;
    _saveTail = _saveTail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prior != null) {
          await MatchArchive.save(
            prefs,
            prior,
            computerSeats: archivedComputerSeats,
          );
        } else if (replay != null) {
          await MatchArchive.save(
            prefs,
            MatchEngine.importReplay(replay),
            replay: replay,
            computerSeats: archivedComputerSeats,
          );
        }
      } on Object {
        if (mounted) fail('Could not archive the previous match.');
      }
    });
  }

  Future<void> _showMatchHistory(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MatchHistoryPage(prefs: prefs)),
    );
  }

  void resume({bool automatic = false}) {
    final replay = savedReplay;
    if (replay == null) return;
    try {
      final loaded = MatchEngine.importReplay(replay);
      final computerSeats = savedAiSeats
          .where((s) => s > 0 && s < loaded.players.length)
          .toSet();
      // Shared-device games need an explicit choice of who is resuming.
      // Otherwise an old local save opens a privacy handoff on every launch.
      if (automatic && computerSeats.length != loaded.players.length - 1) {
        return;
      }
      ai.pause();
      setState(() {
        match = loaded;
        aiSeats = computerSeats;
        matchBotDifficulty = savedBotDifficulty;
        aiMoveCount = 0;
        aiError = null;
        page = Page.board;
        handoff =
            !aiSeats.contains(loaded.actingSeat) &&
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
    for (var i = 1; i <= 6; i++) TextEditingController(text: 'Player $i'),
  ];

  @override
  void dispose() {
    ai.pause();
    _aiRecoveryTimer?.cancel();
    _localTradeGraceTimer?.cancel();
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
    if (savedReplay != null &&
        MatchEngine.importReplay(savedReplay!).phase != MatchPhase.finished) {
      final replace = await showDialog<bool>(
        context: dialogContext,
        builder: (context) => CompactAlertDialog(
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
      _archiveReplacedMatch();
      final firstComputer = humanSeats;
      final botNames = [
        "Rowan",
        "Elara",
        "Cedric",
        "Mira",
        "Oswin",
        "Tamsin",
        "Alden",
        "Briar",
        "Bob",
        "Alice",
        "Dave",
        "Sue",
        "Sam",
        "Pat",
      ]..shuffle(math.Random());
      final s = MatchEngine.newGame(
        [
          for (var i = 0; i < seats; i++)
            i >= firstComputer
                ? botNames[i - firstComputer]
                : names[i].text.trim(),
        ],
        widget.worldSeedFactory(),
        cardDeckVersion: 2,
        turnOrder: widget.randomizeTurnOrder
            ? (List.generate(seats, (i) => i)..shuffle(math.Random()))
            : null,
      );
      ai.pause();
      setState(() {
        match = s;
        matchBotDifficulty = botDifficulty;
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
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Return to board',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Text(
                      'Actions',
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final entry in [
                      ('Rules', Page.rules, Icons.menu_book),
                      ('Home', Page.home, Icons.home_outlined),
                    ])
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            setState(() => page = entry.$2);
                          },
                          icon: Icon(entry.$3),
                          label: Text(entry.$1),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) _syncAi();
  }

  void dispatch(MatchEvent event) {
    if (page != Page.board || handoff || match == null) return;
    final previous = match!;
    // Replying to an outstanding computer offer is not a turn-owner action.
    // A human must be able to accept/decline/counter during the bot's turn.
    bool eligibleTradeRecipient(int seat, int? offerId) =>
        !aiSeats.contains(seat) &&
        previous.offers.any(
          (offer) =>
              offer.proposer == previous.active &&
              (offerId == null || offer.id == offerId) &&
              offer.canRespond(seat),
        );
    final humanTradeReply = event is RespondTrade
        ? eligibleTradeRecipient(event.player, event.offerId)
        : event is ProposeTrade && event.counterOf != null
        ? eligibleTradeRecipient(
            event.counterActor ??
                (previous.offers
                        .where((o) => o.id == event.counterOf)
                        .firstOrNull
                        ?.target ??
                    -1),
            event.counterOf,
          )
        : false;
    if (aiActing && !humanTradeReply) return;
    if (aiSeats.contains(previous.actingSeat) && !humanTradeReply) return;
    try {
      final next = MatchEngine.apply(previous, event);
      final oldOwner = previous.actingSeat;
      final nextOwner = next.actingSeat;
      setState(() {
        handoff =
            oldOwner != nextOwner &&
            !aiSeats.contains(nextOwner) &&
            !oneHumanMatch;
        match = next;
      });
      _save(next, previous: previous);
      _syncAi();
    } on StateError catch (error) {
      fail(error.message);
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
      if (savedReplay != null &&
          MatchEngine.importReplay(savedReplay!).phase != MatchPhase.finished) {
        final replace = await showDialog<bool>(
          context: dialogContext,
          builder: (context) => CompactAlertDialog(
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
      _archiveReplacedMatch();
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
      final optionList = ListView(
        padding: EdgeInsets.all(isCompactLandscape(context) ? 8 : 20),
        children: [
          if (!isCompactLandscape(context))
            Text(
              'Match setup',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          const SizedBox(height: 8),
          Text(
            'Choose who plays. All opponents run locally.',
            style: TextStyle(
              fontSize: 12,
              color: gameColor(context, const Color(0xffabbfc2)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Game options',
            style: TextStyle(
              color: gameColor(context, const Color(0xffefd6a3)),
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
                onSelected: (_) =>
                    _updateSetup(() => computerOpponents = false),
              ),
              ChoiceChip(
                label: const Text('Vs bots'),
                selected: computerOpponents,
                onSelected: (_) => _updateSetup(() => computerOpponents = true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final count in [3, 4, 5, 6])
                ChoiceChip(
                  label: Text('$count players'),
                  selected: seats == count,
                  onSelected: (_) => _updateSetup(() {
                    seats = count;
                    if (aiOpponentCount >= seats) aiOpponentCount = seats - 1;
                  }),
                ),
            ],
          ),
        ],
      );
      final options = isCompactLandscape(context)
          ? Column(
              children: [
                CompactPageHeader(
                  title: 'Match setup',
                  onBack: () => setState(() => page = Page.home),
                  backTooltip: 'Back to Home',
                ),
                Expanded(child: optionList),
              ],
            )
          : optionList;
      final players = Column(
        children: [
          Expanded(
            child: ListView(
              padding: isCompactLandscape(context)
                  ? const EdgeInsets.fromLTRB(10, 8, 10, 4)
                  : const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                if (isCompactLandscape(context)) ...[
                  Text(
                    'Player names',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (computerOpponents) ...[
                    const SizedBox(height: 2),
                    const Text(
                      'Computer opponents',
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      '$humanSeats ${humanSeats == 1 ? 'human' : 'humans'} · $aiOpponentCount ${aiOpponentCount == 1 ? 'computer' : 'computers'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: gameColor(context, const Color(0xffabbfc2)),
                      ),
                    ),
                  ],
                ] else
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
                          label: Text('$i ${i == 1 ? 'bot' : 'bots'}'),
                          selected: aiOpponentCount == i,
                          onSelected: (_) =>
                              _updateSetup(() => aiOpponentCount = i),
                        ),
                    ],
                  ),
                ],
                if (computerOpponents) ...[
                  const SizedBox(height: 12),
                  const Text('Bot difficulty'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final level in BotDifficulty.values)
                        ChoiceChip(
                          label: Text(level.label),
                          selected: botDifficulty == level,
                          onSelected: (_) =>
                              _updateSetup(() => botDifficulty = level),
                        ),
                    ],
                  ),
                  Text(switch (botDifficulty) {
                    BotDifficulty.easy =>
                      'Relaxed play with fewer actions per turn.',
                    BotDifficulty.medium =>
                      'More active play with less precise planning.',
                    BotDifficulty.hard =>
                      'Full strategy and longer action sequences.',
                  }),
                ],
                if (!isCompactLandscape(context)) ...[
                  const SizedBox(height: 8),
                  Text(
                    computerOpponents
                        ? '$humanSeats ${humanSeats == 1 ? 'human' : 'humans'} · $aiOpponentCount ${aiOpponentCount == 1 ? 'computer' : 'computers'}'
                        : '$seats humans · pass the device between turns',
                    style: TextStyle(
                      color: gameColor(context, const Color(0xffabbfc2)),
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
                ] else
                  const SizedBox(height: 6),
                for (var i = 0; i < humanSeats; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: isCompactLandscape(context) ? 4 : 10,
                    ),
                    child: TextField(
                      controller: names[i],
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Player ${i + 1}',
                        isDense: isCompactLandscape(context),
                        contentPadding: isCompactLandscape(context)
                            ? const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              )
                            : null,
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
                if (savedReplay != null &&
                    MatchEngine.importReplay(savedReplay!).phase !=
                        MatchPhase.finished)
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
        color: gameColor(context, const Color(0xff101e25)),
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
                    // Two option chips should not take half of a portrait screen.
                    if (bounds.maxHeight > bounds.maxWidth)
                      SizedBox(
                        height: math.min(276, bounds.maxHeight * .39),
                        child: options,
                      )
                    else
                      Expanded(child: options),
                    Expanded(child: players),
                  ],
                ),
        ),
      );
    },
  );

  Widget _compactRules(BuildContext context) => SafeArea(
    child: Column(
      children: [
        CompactPageHeader(
          title: 'The founding rules',
          onBack: () => setState(() => page = Page.home),
          backTooltip: 'Back to Home',
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: const [
                    Text(
                      'The essentials',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    _Rule(
                      '1 · Claim',
                      'Place two free Village–Road pairs in snake order. Leave a gap between villages.',
                    ),
                    _Rule(
                      '2 · Roll',
                      'Dice earn goods from nearby terrain. A seven moves the Bandit.',
                    ),
                    _Rule(
                      '3 · Build and trade',
                      'Spend goods on roads, Villages, Towns and Capitals, or exchange with other players.',
                    ),
                    _Rule(
                      '4 · Win',
                      'First to 15 Renown wins. Villages = 1, Towns = 2, Capitals = 4, crown road = 2.',
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: const [
                    Text(
                      'Advanced play',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    _Rule(
                      'Town Developments',
                      'Innovation, Commerce and Governance have five tiers, producing commodities.',
                    ),
                    _Rule(
                      'Reaver Fleet and Guards',
                      'Guards defend; fortifications protect Towns during invasions.',
                    ),
                    _Rule(
                      'Reactions',
                      'Intercept theft, counter cards and pledge invasion aid when eligible.',
                    ),
                    _Rule(
                      'Catch-up',
                      'Players three points behind can make a limited 3:1 bank exchange.',
                    ),
                    Divider(height: 16),
                    Text(
                      'Glossary',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    _Rule(
                      'Basic goods',
                      'Wood, brick, wheat, sheep and ore pay for roads, structures and Guards.',
                    ),
                    _Rule(
                      'Commodities',
                      'Paper, cloth and coin come from developed Towns and help build Capitals.',
                    ),
                    _Rule(
                      'Renown',
                      'Reach 15 to win. Charter Points and Guardian’s Honour also count.',
                    ),
                    _Rule(
                      'Bandit',
                      'A seven relocates the Bandit and may cause discards or theft.',
                    ),
                    _Rule(
                      'Seed and replay',
                      'Saved events and the world seed recreate a match.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _showSettings(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (context, refresh) {
            final compact = isCompactLandscape(context);
            final tilePadding = compact
                ? const EdgeInsets.symmetric(horizontal: 10)
                : null;
            final hints = FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, snapshot) {
                final prefs = snapshot.data;
                return SwitchListTile(
                  dense: compact,
                  contentPadding: tilePadding,
                  title: const Text('Gameplay hints'),
                  value: prefs?.getBool('gameplay_hints_enabled') ?? true,
                  onChanged: prefs == null
                      ? null
                      : (value) async {
                          await prefs.setBool('gameplay_hints_enabled', value);
                          refresh(() {});
                        },
                );
              },
            );
            final icons = ValueListenableBuilder<ResourceIconStyle>(
              valueListenable: resourceIconStyle,
              builder: (context, style, _) => ListTile(
                dense: compact,
                contentPadding: tilePadding,
                title: const Text('Resource icons'),
                trailing: DropdownButton<ResourceIconStyle>(
                  value: style,
                  isDense: compact,
                  items: [
                    for (final option in ResourceIconStyle.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) selectResourceIconStyle(value);
                  },
                ),
              ),
            );
            final appearance = ListTile(
              dense: compact,
              contentPadding: tilePadding,
              title: const Text('Appearance'),
              trailing: DropdownButton<ThemeMode>(
                value: themeMode,
                isDense: compact,
                items: [
                  for (final mode in ThemeMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.name)),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() => themeMode = value);
                  refresh(() {});
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('themeMode', value.name);
                },
              ),
            );
            final background = SwitchListTile(
              dense: compact,
              contentPadding: tilePadding,
              title: const Text('Pause offline games in background'),
              subtitle: compact
                  ? null
                  : const Text('Online games always continue.'),
              value: pauseInBackground,
              onChanged: (value) async {
                setState(() => pauseInBackground = value);
                refresh(() {});
                _syncAi();
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('pauseInBackground', value);
              },
            );
            final delay = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: compact,
                  contentPadding: tilePadding,
                  title: const Text('Computer action delay'),
                  trailing: compact
                      ? Text('${aiDelaySeconds.toStringAsFixed(1)}s')
                      : null,
                  subtitle: compact
                      ? null
                      : Text(
                          '${aiDelaySeconds.toStringAsFixed(1)} seconds · press Space to finish computer turns immediately',
                        ),
                ),
                Slider(
                  value: aiDelaySeconds,
                  min: 0.2,
                  max: 5,
                  divisions: 24,
                  onChanged: (value) async {
                    setState(() => aiDelaySeconds = value);
                    ai.delay = Duration(milliseconds: (value * 1000).round());
                    refresh(() {});
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setDouble('aiDelaySeconds', value);
                  },
                ),
              ],
            );
            return Scaffold(
              appBar: compact || MediaQuery.sizeOf(context).width < 900
                  ? null
                  : AppBar(title: const Text('Settings')),
              body: compact
                  ? SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            CompactPageHeader(
                              title: 'Settings',
                              onBack: () => Navigator.of(context).pop(),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ListView(
                                      children: [hints, icons, appearance],
                                    ),
                                  ),
                                  const VerticalDivider(width: 1),
                                  Expanded(
                                    child: ListView(
                                      children: [background, delay],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        if (MediaQuery.sizeOf(context).width < 900)
                          CompactPageHeader(
                            title: 'Settings',
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        hints,
                        icons,
                        appearance,
                        background,
                        delay,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

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
      themeMode: themeMode,
      home:
          kIsWeb &&
              !_dismissedInitialP2pLink &&
              P2pTransport.initialLink() != null
          ? P2pRoomPage(
              onExitToHome: () =>
                  setState(() => _dismissedInitialP2pLink = true),
            )
          : Builder(
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
                        event.logicalKey == LogicalKeyboardKey.space &&
                        aiActing &&
                        page == Page.board &&
                        Navigator.of(context).canPop() == false &&
                        FocusManager.instance.primaryFocus?.context?.widget
                            is! EditableText) {
                      _fastForwardBots();
                      return KeyEventResult.handled;
                    }
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape &&
                        (page != Page.home || Navigator.of(context).canPop())) {
                      Navigator.of(context).maybePop();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Scaffold(
                    appBar:
                        page == Page.board ||
                            MediaQuery.sizeOf(context).width < 900
                        ? null
                        : AppBar(
                            actions: [
                              IconButton(
                                tooltip: 'Settings',
                                icon: const Icon(Icons.settings),
                                onPressed: () => _showSettings(context),
                              ),
                            ],
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
                            onSettings: () => _showSettings(context),
                            onNew: () => setState(() => page = Page.setup),
                            onContinue: savedReplay == null ? null : resume,
                            onRules: () => setState(() => page = Page.rules),
                            onImport: () => importMatch(context),
                            onHistory: () => _showMatchHistory(context),
                            // Use one interoperable transport at the primary
                            // entry point on Android, Linux and web.
                            onP2p: null,
                            onLan: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const P2pRoomPage(),
                              ),
                            ),
                          ),
                          Page.setup => LayoutBuilder(
                            builder: (context, bounds) =>
                                bounds.maxWidth >= 1200
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
                                    onSettings: () => _showSettings(context),
                                    pauseInBackground: pauseInBackground,
                                    computerSeats: aiSeats,
                                    visibleSeat: oneHumanMatch
                                        ? 0
                                        : current.actingSeat,
                                    observing: aiActing,
                                    fastForwardingBots: _fastForwardingBots,
                                    onFastForward: aiActing
                                        ? _fastForwardBots
                                        : null,
                                    tradeReplyAllowed:
                                        oneHumanMatch &&
                                        match != null &&
                                        match!.offers.any(
                                          (offer) =>
                                              offer.proposer == match!.active &&
                                              offer.canRespond(0),
                                        ),
                                  ),
                          Page.rules =>
                            isCompactLandscape(context)
                                ? _compactRules(context)
                                : Center(
                                    key: const ValueKey('stone-rules-page'),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 680,
                                      ),
                                      child: ListView(
                                        // Leave space for the floating mobile
                                        // back button, including at large text scales.
                                        padding: EdgeInsets.fromLTRB(
                                          20,
                                          MediaQuery.sizeOf(context).width < 900
                                              ? 62
                                              : 20,
                                          20,
                                          20,
                                        ),
                                        children: [
                                          Text(
                                            'The founding rules',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'The essentials',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge,
                                          ),
                                          const SizedBox(height: 12),
                                          const _Rule(
                                            '1 · Claim',
                                            'Each seat places two free Village and Road pairs in a snake draft. Leave a gap between villages.',
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
                                            'First to 15 Renown wins. Village = 1, Town = 2, Capital = 4; the crown road of at least five sides earns 2.',
                                          ),
                                          const Divider(height: 24),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: const [
                                              Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 12,
                                                ),
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
                                                'Reaver Fleet and Guards',
                                                'Activate and promote Guards to defend the realm. Fortifications shelter Towns when an Invasion succeeds.',
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: const [
                                              Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 12,
                                                ),
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
                                                'Wood, brick, wheat, sheep and ore pay for roads, structures and Guards.',
                                              ),
                                              _Rule(
                                                'Commodities',
                                                'Paper, cloth and coin come from developed Towns and help build Capitals.',
                                              ),
                                              _Rule(
                                                'Renown',
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
                        if (MediaQuery.sizeOf(context).width < 900 &&
                            !isCompactLandscape(context) &&
                            (page == Page.setup || page == Page.rules))
                          Positioned(
                            top: MediaQuery.paddingOf(context).top + 4,
                            right: MediaQuery.paddingOf(context).right + 8,
                            child: IconButton.filledTonal(
                              tooltip: 'Back to Home',
                              onPressed: () => setState(() => page = Page.home),
                              icon: const Icon(Icons.arrow_back),
                            ),
                          ),
                        if (page == Page.board && handoff && current != null)
                          Positioned.fill(
                            child: Material(
                              color: gameColor(
                                context,
                                const Color(0xff101e25),
                              ),
                              child: Center(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(20),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 560,
                                    ),
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.lock_outline,
                                                  size: 44,
                                                  color: gameColor(
                                                    context,
                                                    const Color(0xffe5c183),
                                                  ),
                                                ),
                                                const SizedBox(width: 20),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
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
                                              builder: (context) =>
                                                  TextButton.icon(
                                                    onPressed: () =>
                                                        _showMatchActions(
                                                          context,
                                                        ),
                                                    icon: const Icon(
                                                      Icons.layers_outlined,
                                                    ),
                                                    label: const Text(
                                                      'Actions',
                                                    ),
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
  Widget build(BuildContext context) => CompactAlertDialog(
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
  Widget build(BuildContext context) {
    final compact = isCompactLandscape(context);
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 8 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: compact
                ? Theme.of(context).textTheme.titleSmall
                : Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: compact ? 2 : 4),
          Text(
            description,
            style: compact ? const TextStyle(fontSize: 12) : null,
          ),
        ],
      ),
    );
  }
}

class _LandingHall extends StatelessWidget {
  const _LandingHall({
    required this.onNew,
    required this.onSettings,
    required this.onContinue,
    required this.onRules,
    required this.onImport,
    required this.onHistory,
    required this.onLan,
    required this.onP2p,
  });
  final VoidCallback onNew, onRules, onImport, onHistory, onLan, onSettings;
  final VoidCallback? onP2p;
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
                    color: gameColor(context, const Color(0xffefd6a3)),
                  ),
                ),
                SizedBox(height: compactLandscape ? 4 : 8),
                Text(
                  'Build, trade and defend your way to 15 Renown.',
                  style: TextStyle(
                    color: gameColor(context, const Color(0xffabbfc2)),
                    fontSize: 13,
                  ),
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
                    if (onP2p != null)
                      TextButton.icon(
                        onPressed: onP2p,
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('P2P multiplayer'),
                      ),
                    TextButton.icon(
                      onPressed: onLan,
                      icon: const Icon(Icons.groups_outlined, size: 18),
                      label: const Text('Host / join multiplayer'),
                    ),
                    TextButton.icon(
                      onPressed: onImport,
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('Import replay'),
                    ),
                    TextButton.icon(
                      onPressed: onHistory,
                      icon: const Icon(Icons.history_toggle_off, size: 18),
                      label: const Text('Match history'),
                    ),
                    Tooltip(
                      message: 'Settings',
                      child: TextButton.icon(
                        onPressed: onSettings,
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: const Text('Settings'),
                      ),
                    ),
                  ],
                ),
                if (!compactLandscape) ...[
                  const SizedBox(height: 12),
                  Text(
                    'OFFLINE PLAY  ·  LOCAL BOTS  ·  3–6 SEATS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.3,
                      color: gameColor(context, const Color(0xff8fa9ac)),
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
        color: gameColor(context, const Color(0xff101e25)),
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
                            Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'WELCOME TO THE TABLE',
                                style: TextStyle(
                                  color: gameColor(
                                    context,
                                    const Color(0xff8fa9ac),
                                  ),
                                  letterSpacing: 2,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(child: menu),
                            Padding(
                              padding: EdgeInsets.all(24),
                              child: Row(
                                children: [
                                  Icon(Icons.save_outlined, size: 20),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Your match saves automatically on this device.',
                                      style: TextStyle(
                                        color: gameColor(
                                          context,
                                          const Color(0xffabbfc2),
                                        ),
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
