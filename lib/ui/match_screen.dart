// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:math' as math;
import 'dart:async';

import 'compact_layout.dart';

import 'package:flutter/material.dart';

import 'dock_label_layout.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/advanced.dart';
import '../engine/cards.dart';
import '../engine/board.dart';
import '../engine/game.dart';
import '../engine/match.dart';
import 'strategy_hand.dart';
import 'labels.dart';
import 'resource_harvest.dart';
import 'resource_icon.dart';
import 'trade_market.dart';
import 'trade_leg.dart';
import 'focus_hint.dart';
import 'gameplay_hint.dart';
import 'match_activity.dart';
import 'emote_icon.dart';
import 'match_end_modal.dart';
import 'board_event_effects.dart';
import 'dice_roll.dart';
import 'invasion_meter.dart';

enum _Move {
  inspect,
  village,
  road,
  upgrade,
  bandit,
  fortify,
  recruit,
  activate,
  promote,
  knightMove,
}

const seatColors = [
  Color(0xff40d5b4),
  Color(0xffffc477),
  Color(0xffd5a6f7),
  Color(0xff8ebdff),
];
const landColors = [
  Color(0xff437c60),
  Color(0xffb46c4d),
  Color(0xffb9a05e),
  Color(0xff90ab61),
  Color(0xff8395a2),
  Color(0xff81705c),
];

class MatchView extends StatefulWidget {
  const MatchView({
    super.key,
    required this.state,
    required this.onEvent,
    this.observing = false,
    this.tradeReplyAllowed = false,
    this.online = false,
    this.onlineView,
    this.viewingSeat,
    this.computerSeats = const <int>{},
    this.visibleSeat,
    this.waitingMessage,
    this.onHome,
    this.onLeaveRoom,
    this.onRules,
    this.onSettings,
    this.pauseInBackground = true,
    this.onEmote,
    this.networkEmote,
    this.networkEmoteSeat,
    this.networkEmoteSerial = 0,
  });
  final MatchState state;
  final ValueChanged<MatchEvent> onEvent;
  final bool observing;

  /// Off-turn trade recipients can answer offers without acquiring turn control.
  final bool tradeReplyAllowed;
  final bool online;
  final Map<String, dynamic>? onlineView;
  final int? viewingSeat;
  final Set<int> computerSeats;
  final int? visibleSeat;
  final String? waitingMessage;
  final VoidCallback? onHome, onLeaveRoom, onRules;
  final Future<void> Function()? onSettings;
  final bool pauseInBackground;
  final ValueChanged<String>? onEmote;
  final String? networkEmote;
  final int? networkEmoteSeat;
  final int networkEmoteSerial;
  @override
  State<MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<MatchView> with TickerProviderStateMixin {
  final _resourceAnchors = {for (final r in Resource.values) r: LayerLink()};
  _Move choice = _Move.inspect;
  StrategyCard? _mapCard;
  List<PlayStrategyCard> _mapCardOptions = const [];
  bool get _choosingCardTarget =>
      _mapCard != null && _mapCardOptions.isNotEmpty;
  String get _mapCardTargetMessage =>
      '${_mapCard?.name ?? 'Card'}: tap a glowing '
      '${_mapCardUsesRoads
          ? 'road'
          : _mapCardUsesTiles
          ? 'hex'
          : 'junction'}';
  bool get _mapCardUsesRoads => _mapCard?.power == CardPower.freeRoad;
  bool get _mapCardUsesTiles =>
      {CardPower.moveBandit, CardPower.massExhaust}.contains(_mapCard?.power);
  Set<int> get _mapCardEdges => _mapCardUsesRoads
      ? {
          for (final option in _mapCardOptions)
            if (option.vertex != null) option.vertex!,
        }
      : {};
  Set<int> get _mapCardTiles => _mapCardUsesTiles
      ? {
          for (final option in _mapCardOptions)
            if (option.tile != null) option.tile!,
        }
      : {};
  Set<int> get _mapCardVertices {
    if (!_choosingCardTarget || _mapCardUsesRoads || _mapCardUsesTiles) {
      return {};
    }
    if (_mapCard?.power == CardPower.seizeGood) {
      final rivals = {
        for (final option in _mapCardOptions)
          if (option.target != null) option.target!,
      };
      return {
        for (final entry in s.sites.entries)
          if (rivals.contains(entry.value.owner)) entry.key,
      };
    }
    return {
      for (final option in _mapCardOptions)
        if (option.vertex != null) option.vertex!,
    };
  }

  int? selectedKnight;
  Size? _boardSize;
  Offset? _hoverPosition;
  RollDice? _rollingDice;
  int _diceAnimationSerial = 0;
  late final AnimationController _roadController;
  late final Animation<double> _roadReveal;
  int? _animatedRoad;
  int? _animatedRoadStart;
  Timer? _turnClock;
  int _secondsLeft = 90;
  int? _expiredEventCount;
  bool _endModalDismissed = false;
  bool _hintsEnabled = true;
  bool _hintsLoaded = false;
  final Set<String> _seenHints = {};
  String? _dismissedHintContext;
  bool _incomingTradeOpen = false;
  bool _tradeComposerOpen = false;
  int? _incomingDialogOfferId;
  BuildContext? _incomingDialogContext;
  final Set<int> _notifiedTradeOfferIds = {};
  int? _waitingBotOfferId;
  int _botOfferSeconds = 30;
  int? _expiredBotOfferId;
  bool _discardMinimized = false;
  int _discardSecondsLeft = 45;
  bool _discardTimeoutSent = false;
  final Map<Resource, int> _discardSelection = {};
  _TradeResume? _minimizedTradeComposer;

  Future<void> _loadHints() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hintsEnabled = prefs.getBool('gameplay_hints_enabled') ?? true;
      _seenHints.addAll(prefs.getStringList('gameplay_hints_seen_v1') ?? []);
      _hintsLoaded = true;
    });
  }

  Future<void> _setHintsEnabled(bool enabled) async {
    setState(() => _hintsEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gameplay_hints_enabled', enabled);
  }

  final _realmHintTarget = GlobalKey();
  final _actionsHintTarget = GlobalKey();
  final _boardHintTarget = GlobalKey();
  final _panelHintTarget = GlobalKey();
  final _tabHintTargets = List.generate(3, (_) => GlobalKey());

  String get _hintContext =>
      '${s.seed}:${s.phase}:${s.tactical?.id}:$_tab:$move:$_mobilePage';

  GameplayHint? get _activeGameplayHint {
    if (!_hintsLoaded ||
        !_hintsEnabled ||
        widget.observing ||
        _dismissedHintContext == _hintContext) {
      return null;
    }
    String? id;
    if (s.tactical != null) {
      if (s.tactical!.responder != viewerSeat) return null;
      id = 'response_${s.tactical!.kind.name}';
    } else {
      if (s.active != viewerSeat) return null;
      id = switch (s.phase) {
        MatchPhase.setupVillage =>
          s.setupStep < s.players.length ? 'setupVillage' : 'setupTown',
        MatchPhase.setupRoad => 'setupRoad',
        MatchPhase.roll => 'roll',
        MatchPhase.bandit => 'bandit',
        MatchPhase.invasion => 'invasion',
        MatchPhase.finished => null,
        MatchPhase.actions =>
          move != _Move.inspect
              ? move.name
              : switch (_tab) {
                  1 => 'trade',
                  2 => 'cards',
                  3 => 'realm',
                  _ =>
                    !_seenHints.contains('town') &&
                            s.players[viewerSeat].developments.values.every(
                              (level) => level == 0,
                            ) &&
                            s.sites.values.any(
                              (site) =>
                                  site.owner == viewerSeat &&
                                  site.structure != Structure.village,
                            )
                        ? 'town'
                        : 'actions',
                },
      };
    }
    return id == null || _seenHints.contains(id) ? null : gameplayHints[id];
  }

  Future<void> _dismissGameplayHint(GameplayHint hint) async {
    setState(() {
      _seenHints.add(hint.id);
      _dismissedHintContext = _hintContext;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'gameplay_hints_seen_v1',
      _seenHints.toList()..sort(),
    );
  }

  Widget _gameplayHint(bool mobile, GameplayHint hint) {
    final onMap = !mobile || _mobilePage == null;
    final target = hint.id == 'town'
        ? (mobile && onMap ? _actionsHintTarget : _realmHintTarget)
        : s.tactical != null
        ? _panelHintTarget
        : ['trade', 'cards', 'realm', 'actions'].contains(hint.id)
        ? (mobile && onMap
              ? _actionsHintTarget
              : hint.id == 'realm'
              ? _realmHintTarget
              : _tabHintTargets[_tab])
        : onMap
        ? _boardHintTarget
        : _panelHintTarget;
    return FocusHint(
      key: ValueKey(
        hint.id == 'town' ? 'town-production-hint' : 'gameplay-hint-${hint.id}',
      ),
      target: target,
      title: hint.title,
      explanation: hint.explanation,
      actionLabel: hint.id == 'town' ? 'Realm' : 'Got it',
      onOpen: () {
        unawaited(_dismissGameplayHint(hint));
        if (hint.id == 'town') {
          setState(() {
            _tab = 3;
            if (mobile) _mobilePage = -1;
            _dismissedHintContext = _hintContext;
          });
        }
      },
      onDismiss: () => unawaited(_dismissGameplayHint(hint)),
    );
  }

  late final AnimationController _numberPulseController;
  late final AnimationController _banditBlockController;
  int? _humiliatedBanditTile;
  late final AnimationController _cardsTabController;
  late final AnimationController _cityFallController;
  late final AnimationController _longestRoadController;
  int? _longestRoadWinner;
  List<int> _longestRoadRoute = const [];
  bool _unseenCard = false;
  String? _newCardNotice;
  Timer? _newCardTimer;
  String? _fallenCityOwner;
  int _fallenCityVp = 0;

  @override
  void initState() {
    super.initState();
    unawaited(loadResourceIcons());
    unawaited(_loadHints());
    _scheduleIncomingTrade();
    _turnClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          s.phase == MatchPhase.finished ||
          (_activeGameplayHint != null &&
              s.pendingDiscards.isEmpty &&
              s.offers.isEmpty &&
              (ModalRoute.of(context)?.isCurrent ?? true)) ||
          (!widget.online &&
              widget.pauseInBackground &&
              WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed)) {
        return;
      }
      final incomingBotOffer = s.offers
          .where(
            (o) =>
                o.canRespond(viewerSeat) &&
                widget.computerSeats.contains(o.proposer) &&
                o.proposer == s.active,
          )
          .firstOrNull;
      if (_waitingBotOfferId != incomingBotOffer?.id) {
        _waitingBotOfferId = incomingBotOffer?.id;
        _botOfferSeconds = 30;
      }
      if (incomingBotOffer != null && !widget.observing) {
        if (_botOfferSeconds > 0) setState(() => _botOfferSeconds--);
        if (_botOfferSeconds == 0 &&
            _expiredBotOfferId != incomingBotOffer.id) {
          _expiredBotOfferId = incomingBotOffer.id;
          if (_incomingTradeOpen &&
              !(ModalRoute.of(context)?.isCurrent ?? true)) {
            Navigator.of(context)
                .popUntil((route) => route == ModalRoute.of(context));
          }
          send(RespondTrade(viewerSeat, false, offerId: incomingBotOffer.id));
          return;
        }
      }
      if (s.pendingDiscards.containsKey(viewerSeat) &&
          s.actingSeat == viewerSeat &&
          !widget.observing) {
        if (_discardSecondsLeft > 0) setState(() => _discardSecondsLeft--);
        if (_discardSecondsLeft == 0 && !_discardTimeoutSent) {
          _discardTimeoutSent = true;
          if (_discardDialogOpen &&
              !(ModalRoute.of(context)?.isCurrent ?? true)) {
            Navigator.of(context)
                .popUntil((route) => route == ModalRoute.of(context));
          }
          final fallback = MatchEngine.idleEvent(s);
          if (fallback != null) send(fallback);
          return;
        }
      }
      if (_secondsLeft > 0) setState(() => _secondsLeft--);
      if (_secondsLeft == 0 &&
          !widget.online &&
          (!widget.observing ||
              s.offers.any(
                (o) => o.canRespond(viewerSeat) && o.proposer == s.active,
              )) &&
          _expiredEventCount != s.events.length) {
        final unanswered = s.offers
            .where((o) => o.canRespond(viewerSeat) && o.proposer == s.active)
            .firstOrNull;
        final event = unanswered != null
            ? RespondTrade(viewerSeat, false, offerId: unanswered.id)
            : MatchEngine.idleEvent(s);
        if (event != null) {
          _expiredEventCount = s.events.length;
          if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
            Navigator.of(context)
                .popUntil((route) => route == ModalRoute.of(context));
          }
          send(event);
        }
      }
    });
    _roadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 1,
    );
    _roadReveal = CurvedAnimation(
      parent: _roadController,
      curve: Curves.easeOutCubic,
    );
    _cardsTabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2900),
      value: 1,
    );
    _cityFallController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3400),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _fallenCityOwner = null);
          }
        });
    _longestRoadController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3200),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _longestRoadWinner = null);
          }
        });
    _numberPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
      value: 1,
    );
    _banditBlockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1850),
      value: 1,
    );
  }

  MatchState get s => widget.state;
  PlayerState get inventoryOwner => s.players[widget.viewingSeat ?? viewerSeat];
  int get viewerSeat =>
      widget.visibleSeat ?? widget.viewingSeat ?? s.actingSeat;
  _Move get move => switch (s.phase) {
    MatchPhase.setupVillage => _Move.village,
    MatchPhase.setupRoad => _Move.road,
    MatchPhase.bandit => _Move.bandit,
    _ => choice,
  };
  bool _discardDialogOpen = false;

  void _scheduleDiscardDialog() {
    if (_discardDialogOpen ||
        _discardMinimized ||
        widget.observing ||
        !s.pendingDiscards.containsKey(viewerSeat) ||
        s.actingSeat != viewerSeat) {
      return;
    }
    _discardDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final seat = viewerSeat;
      final required = s.pendingDiscards[seat];
      if (required == null || widget.observing) {
        _discardDialogOpen = false;
        return;
      }
      final selected = _discardSelection;
      final hand = Map<Resource, int>.of(s.players[seat].stores);
      final result = await showDialog<Map<Resource, int>>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => PopScope(
          canPop: true,
          child: StatefulBuilder(
            builder: (context, update) {
              final total = selected.values.fold<int>(0, (a, b) => a + b);
              return CompactAlertDialog(
                title: Text('${s.players[seat].id}: discard resources'),
                content: SizedBox(
                  width: 380,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'A 7 was rolled. Choose $required resources to discard (half your hand, rounded down).',
                        ),
                        const SizedBox(height: 12),
                        Text('$total / $required selected'),
                        for (final good in Resource.values)
                          if ((hand[good] ?? 0) > 0)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${good.displayName} (${hand[good]} held)',
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Keep one more ${good.displayName}',
                                  onPressed: (selected[good] ?? 0) == 0
                                      ? null
                                      : () => update(
                                          () => selected[good] =
                                              selected[good]! - 1,
                                        ),
                                  icon: const Icon(Icons.remove),
                                ),
                                Text('${selected[good] ?? 0}'),
                                IconButton(
                                  tooltip: 'Discard one ${good.displayName}',
                                  onPressed:
                                      total >= required ||
                                          (selected[good] ?? 0) >= hand[good]!
                                      ? null
                                      : () => update(
                                          () => selected[good] =
                                              (selected[good] ?? 0) + 1,
                                        ),
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton.icon(
                    key: const ValueKey('minimize-discard'),
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_fullscreen, size: 17),
                    label: const Text('Later'),
                  ),
                  FilledButton(
                    onPressed: total == required
                        ? () => Navigator.pop(dialogContext, selected)
                        : null,
                    child: Text('Discard $required resources'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      _discardDialogOpen = false;
      if (mounted && result == null && s.pendingDiscards.containsKey(seat)) {
        setState(() => _discardMinimized = true);
      }
      if (mounted &&
          result != null &&
          s.actingSeat == seat &&
          s.pendingDiscards[seat] == required) {
        send(DiscardResources(seat, result));
      }
    });
  }

  void send(MatchEvent event) {
    final isTradeResponse =
        event is RespondTrade ||
        (event is ProposeTrade && event.counterOf != null);
    if (widget.observing && !(widget.tradeReplyAllowed && isTradeResponse)) {
      return;
    }
    if (widget.online && s.actingSeat != viewerSeat && !isTradeResponse) {
      return;
    }
    widget.onEvent(event);
    setState(() {
      choice = _Move.inspect;
      selectedKnight = null;
      _mapCard = null;
      _mapCardOptions = const [];
    });
  }

  void _chooseCardTarget(StrategyCard card, List<PlayStrategyCard> options) {
    if (widget.observing || s.active != viewerSeat || options.isEmpty) return;
    setState(() {
      _mapCard = card;
      _mapCardOptions = List.unmodifiable(options);
      choice = _Move.inspect;
      selectedKnight = null;
      _mobilePage = null;
    });
  }

  Future<void> _tapCardTarget(Offset tap, Size size) async {
    final geometry = BoardGeometry(size);
    List<PlayStrategyCard> matches = [];
    if (_mapCardUsesRoads) {
      final edge = _roadNear(tap, geometry, _mapCardEdges);
      if (edge != null) {
        matches = _mapCardOptions.where((o) => o.vertex == edge).toList();
      }
    } else if (_mapCardUsesTiles) {
      for (final tile in _mapCardTiles) {
        if ((tap - geometry.tile(s.board.tiles[tile].position)).distance <=
            geometry.radius * .72) {
          matches = _mapCardOptions.where((o) => o.tile == tile).toList();
          break;
        }
      }
    } else {
      int? nearest;
      var distance = double.infinity;
      for (final vertex in _mapCardVertices) {
        final d = (tap - geometry.vertex(s.topology.vertices[vertex])).distance;
        if (d < distance) {
          distance = d;
          nearest = vertex;
        }
      }
      if (nearest != null && distance <= math.max(22, geometry.radius * .47)) {
        if (_mapCard?.power == CardPower.seizeGood) {
          final owner = s.sites[nearest]?.owner;
          matches = _mapCardOptions.where((o) => o.target == owner).toList();
        } else {
          matches = _mapCardOptions.where((o) => o.vertex == nearest).toList();
        }
      }
    }
    if (matches.isEmpty || !mounted) return;
    PlayStrategyCard? selected;
    if (matches.length == 1) {
      selected = matches.single;
    } else {
      final choices = {
        for (final option in matches)
          if (option.receive != null) option.receive!: option,
      };
      selected = await showDialog<PlayStrategyCard>(
        context: context,
        builder: (dialogContext) => CompactAlertDialog(
          title: Text('Play ${_mapCard?.name ?? 'card'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose which resource to take:'),
              for (final entry in choices.entries)
                ListTile(
                  title: Text(entry.key.displayName),
                  onTap: () => Navigator.pop(dialogContext, entry.value),
                ),
            ],
          ),
        ),
      );
    }
    if (mounted &&
        selected != null &&
        _choosingCardTarget &&
        s.active == viewerSeat) {
      send(selected);
    }
  }

  int? _roadNear(Offset tap, BoardGeometry g, Iterable<int> edges) {
    int? closest;
    var distance = double.infinity;
    for (final id in edges) {
      final edge = s.topology.edges[id];
      final a = g.vertex(s.topology.vertices[edge.a]);
      final b = g.vertex(s.topology.vertices[edge.b]);
      final ab = b - a;
      final fraction =
          (((tap.dx - a.dx) * ab.dx + (tap.dy - a.dy) * ab.dy) /
                  (ab.dx * ab.dx + ab.dy * ab.dy))
              .clamp(0.0, 1.0);
      final d = (tap - (a + ab * fraction)).distance;
      if (d < distance) {
        distance = d;
        closest = id;
      }
    }
    return distance <= math.max(18, g.radius * .33) ? closest : null;
  }

  Future<void> _confirmRoad(int edge) async {
    if (!MatchEngine.legalRoad(s, edge)) return;
    final cost = _costLabel(MatchEngine.effectiveRoadCost(s));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => CompactAlertDialog(
        title: const Text('Build this road?'),
        content: Text('Cost: $cost'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Build road'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true && MatchEngine.legalRoad(s, edge)) {
      send(PlaceRoad(edge));
    }
  }

  Future<void> _offerRoadExtension() async {
    final available = MatchEngine.legalEdges(s).isNotEmpty;
    final choose = await showDialog<bool>(
      context: context,
      builder: (context) => CompactAlertDialog(
        title: const Text('Extend your road?'),
        content: Text(
          'Cost: ${_costLabel(MatchEngine.effectiveRoadCost(s))}. '
          '${available ? 'Choose a glowing open edge to connect to your network.' : 'No affordable road placements are available this turn.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: available ? () => Navigator.pop(context, true) : null,
            child: const Text('Choose location'),
          ),
        ],
      ),
    );
    if (mounted && choose == true && s.phase == MatchPhase.actions) {
      setState(() => choice = _Move.road);
    }
  }

  String? _boardHover(Offset point, Size size) {
    if (widget.observing || s.tactical != null) return null;
    final g = BoardGeometry(size);
    if (_choosingCardTarget) {
      if (_mapCardUsesRoads && _roadNear(point, g, _mapCardEdges) != null) {
        return 'Play ${_mapCard!.name} · build this road';
      }
      if (_mapCardUsesTiles &&
          _mapCardTiles.any(
            (tile) =>
                (point - g.tile(s.board.tiles[tile].position)).distance <
                g.radius * .72,
          )) {
        return 'Play ${_mapCard!.name} on this hex';
      }
      if (_mapCardVertices.any(
        (v) =>
            (point - g.vertex(s.topology.vertices[v])).distance <
            math.max(22, g.radius * .47),
      )) {
        return 'Play ${_mapCard!.name} at this junction';
      }
      return null;
    }
    if (move == _Move.road) {
      return _roadNear(point, g, availableTargets) == null
          ? null
          : s.phase == MatchPhase.setupRoad
          ? 'Place starting road · free'
          : 'Build road · ${_costLabel(MatchEngine.effectiveRoadCost(s))}';
    }
    if (move == _Move.bandit) {
      for (final id in availableTargets) {
        if ((point - g.tile(s.board.tiles[id].position)).distance < g.radius) {
          return 'Move Bandit here · click to choose a neighbour';
        }
      }
      return null;
    }
    if (move != _Move.inspect) {
      final radius = math.max(
        22,
        g.radius * (move == _Move.village || move == _Move.upgrade ? .4 : .45),
      );
      for (final id in availableTargets) {
        if ((point - g.vertex(s.topology.vertices[id])).distance <= radius) {
          return '$_instruction · click to select';
        }
      }
      return null;
    }
    if (s.phase != MatchPhase.actions) return null;
    for (final id in s.knights.keys) {
      if ((point - g.vertex(s.topology.vertices[id])).distance <=
          math.max(22, g.radius * .35)) {
        final actions = [
          if (MatchEngine.legalActivate(s, id)) 'activate',
          if (MatchEngine.legalPromote(s, id)) 'upgrade',
        ];
        return actions.isEmpty
            ? 'Inspect Knight · click for details'
            : 'Inspect Knight · ${actions.join(' or ')} available';
      }
    }
    for (final id in {
      ...MatchEngine.legalVertices(s),
      ...MatchEngine.legalUpgrades(s),
      for (var v = 0; v < s.topology.vertices.length; v++)
        if (MatchEngine.legalRecruit(s, v)) v,
    }) {
      if ((point - g.vertex(s.topology.vertices[id])).distance <=
          math.min(18, g.radius * .3)) {
        return s.sites.containsKey(id)
            ? 'Upgrade settlement · ${_upgradeCostLabel()}'
            : MatchEngine.legalVillage(s, id)
            ? 'Build a settlement · ${_costLabel(MatchEngine.villageCost)}'
            : 'Build Knight · ${_costLabel(MatchEngine.recruitCost)}';
      }
    }
    final road = _roadNear(point, g, [
      ...MatchEngine.legalEdges(s),
      for (final entry in s.roads.entries)
        if (entry.value == s.active) entry.key,
    ]);
    if (road == null) return null;
    return s.roads[road] == s.active
        ? 'Extend your road · click to see options'
        : 'Build road · ${_costLabel(MatchEngine.effectiveRoadCost(s))}';
  }

  Future<void> tapBoard(Offset tap, Size size) async {
    if (_choosingCardTarget) {
      await _tapCardTarget(tap, size);
      return;
    }
    final g = BoardGeometry(size);
    if (move == _Move.village || move == _Move.upgrade) {
      final legal = move == _Move.village
          ? MatchEngine.legalVertices(s)
          : MatchEngine.legalUpgrades(s);
      int? best;
      var distance = double.infinity;
      for (final id in legal) {
        final d = (tap - g.vertex(s.topology.vertices[id])).distance;
        if (d < distance) {
          distance = d;
          best = id;
        }
      }
      if (best != null && distance <= math.max(22, g.radius * .4)) {
        send(move == _Move.village ? PlaceVillage(best) : UpgradeSite(best));
      }
    } else if (move == _Move.road) {
      final best = _roadNear(tap, g, MatchEngine.legalEdges(s));
      if (best != null) {
        if (s.phase == MatchPhase.setupRoad) {
          send(PlaceRoad(best)); // Starting roads are free.
        } else {
          send(PlaceRoad(best));
        }
      }
    } else if ({
      _Move.fortify,
      _Move.recruit,
      _Move.activate,
      _Move.promote,
      _Move.knightMove,
    }.contains(move)) {
      final legal = switch (move) {
        _Move.fortify => [
          for (final v in s.sites.keys)
            if (MatchEngine.legalFort(s, v)) v,
        ],
        _Move.recruit => [
          for (var v = 0; v < s.topology.vertices.length; v++)
            if (MatchEngine.legalRecruit(s, v)) v,
        ],
        _Move.activate => [
          for (final v in s.knights.keys)
            if (MatchEngine.legalActivate(s, v)) v,
        ],
        _Move.promote => [
          for (final v in s.knights.keys)
            if (MatchEngine.legalPromote(s, v)) v,
        ],
        _Move.knightMove =>
          selectedKnight == null
              ? [
                  for (final v in s.knights.keys)
                    if (s.knights[v]!.owner == s.active &&
                        s.knights[v]!.active &&
                        s.knights[v]!.actedTurn != s.turnSerial &&
                        MatchEngine.legalKnightDestinations(s, v).isNotEmpty)
                      v,
                ]
              : MatchEngine.legalKnightDestinations(s, selectedKnight!),
        _ => <int>[],
      };
      int? best;
      var distance = double.infinity;
      for (final v in legal) {
        final d = (tap - g.vertex(s.topology.vertices[v])).distance;
        if (d < distance) {
          distance = d;
          best = v;
        }
      }
      if (best == null || distance > math.max(22, g.radius * .45)) return;
      switch (move) {
        case _Move.fortify:
          send(FortifyTown(best));
          break;
        case _Move.recruit:
          send(RecruitKnight(best));
          break;
        case _Move.activate:
          send(ActivateKnight(best));
          break;
        case _Move.promote:
          send(PromoteKnight(best));
          break;
        case _Move.knightMove:
          if (selectedKnight == null) {
            setState(() => selectedKnight = best);
          } else {
            send(MoveKnight(selectedKnight!, best));
          }
          break;
        default:
          break;
      }
    } else if (move == _Move.bandit) {
      var best = -1;
      var distance = double.infinity;
      for (var i = 0; i < s.board.tiles.length; i++) {
        if (i == s.banditTile) continue;
        final d = (tap - g.tile(s.board.tiles[i].position)).distance;
        if (d < distance) {
          distance = d;
          best = i;
        }
      }
      if (best == -1 || distance >= g.radius) return;
      final victims = widget.online
          ? ((widget.onlineView?["victims"] as Map?)?["$best"] as List?)
                    ?.cast<int>() ??
                <int>[]
          : MatchEngine.banditVictims(s, best);
      if (victims.isEmpty) {
        send(MoveBandit(best));
      } else {
        final chosen = await showDialog<int>(
          context: context,
          barrierDismissible: false,
          builder: (context) => CompactAlertDialog(
            title: const Text('Bandit · choose who to rob'),
            content: const Text(
              'Choose a neighbour. The good is drawn from their hand using the saved seed.',
            ),
            actions: [
              for (final n in victims)
                TextButton(
                  onPressed: () => Navigator.pop(context, n),
                  child: Text(s.players[n].id),
                ),
            ],
          ),
        );
        if (chosen != null && mounted) {
          send(MoveBandit(best, victim: chosen));
        }
      }
    } else {
      if (move == _Move.inspect && s.phase == MatchPhase.actions) {
        for (final entry in s.knights.entries) {
          if ((tap - g.vertex(s.topology.vertices[entry.key])).distance >
              math.max(22, g.radius * .35)) {
            continue;
          }
          final vertex = entry.key;
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => CompactAlertDialog(
              title: Text(
                '${entry.value.rank.name} Knight · strength ${entry.value.rank.strength}',
              ),
              content: Text(
                '${entry.value.active ? 'Active' : 'Inactive'} · Upgrade cost: ${entry.value.rank == KnightRank.champion ? 'Maximum rank' : _costLabel(MatchEngine.promotionCost(entry.value.rank))}. Upgrading requires an active Knight that has not acted this turn.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: MatchEngine.legalPromote(s, vertex)
                      ? () {
                          Navigator.pop(dialogContext);
                          send(PromoteKnight(vertex));
                        }
                      : null,
                  child: const Text('Upgrade Knight'),
                ),
                if (MatchEngine.legalActivate(s, vertex))
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      send(ActivateKnight(vertex));
                    },
                    child: Text(
                      'Activate · ${_costLabel(MatchEngine.activateCost)}',
                    ),
                  ),
              ],
            ),
          );
          return;
        }
        for (final vertex in {
          ...MatchEngine.legalVertices(s),
          ...MatchEngine.legalUpgrades(s),
          for (var v = 0; v < s.topology.vertices.length; v++)
            if (MatchEngine.legalRecruit(s, v)) v,
        }) {
          if ((tap - g.vertex(s.topology.vertices[vertex])).distance >
              math.min(18, g.radius * .3)) {
            continue;
          }
          if (!mounted) return;
          final upgrade = s.sites.containsKey(vertex);
          final canRecruit = MatchEngine.legalRecruit(s, vertex);
          final canVillage = MatchEngine.legalVillage(s, vertex);
          final event = await showDialog<MatchEvent>(
            context: context,
            builder: (context) => CompactAlertDialog(
              title: Text(
                upgrade ? 'Upgrade settlement?' : 'Build at this junction',
              ),
              content: Text(
                upgrade
                    ? _upgradeCostLabel()
                    : 'Choose what to build at junction ${vertex + 1}.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                if (upgrade)
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, UpgradeSite(vertex)),
                    child: const Text('Upgrade settlement'),
                  ),
                if (canVillage)
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, PlaceVillage(vertex)),
                    child: Text(
                      'Build settlement · ${_costLabel(MatchEngine.villageCost)}',
                    ),
                  ),
                if (canRecruit)
                  OutlinedButton(
                    key: const ValueKey('build-knight-at-junction'),
                    onPressed: () =>
                        Navigator.pop(context, RecruitKnight(vertex)),
                    child: Text(
                      'Build Knight · ${_costLabel(s.players[viewerSeat].level(StrategyDeck.governance) >= 4 ? {Resource.wool: 1} : MatchEngine.recruitCost)}',
                    ),
                  ),
              ],
            ),
          );
          if (mounted && event != null) send(event);
          return;
        }
        final near = _roadNear(tap, g, [
          ...MatchEngine.legalEdges(s),
          for (final road in s.roads.entries)
            if (road.value == s.active) road.key,
        ]);
        if (near != null) {
          if (s.roads[near] == s.active) {
            await _offerRoadExtension();
          } else {
            await _confirmRoad(near);
          }
          return;
        }
      }
    }
  }

  List<int> get availableTargets => switch (move) {
    _Move.village => MatchEngine.legalVertices(s),
    _Move.road => MatchEngine.legalEdges(s),
    _Move.upgrade => MatchEngine.legalUpgrades(s),
    _Move.fortify => [
      for (final v in s.sites.keys)
        if (MatchEngine.legalFort(s, v)) v,
    ],
    _Move.recruit => [
      for (var v = 0; v < s.topology.vertices.length; v++)
        if (MatchEngine.legalRecruit(s, v)) v,
    ],
    _Move.activate => [
      for (final v in s.knights.keys)
        if (MatchEngine.legalActivate(s, v)) v,
    ],
    _Move.promote => [
      for (final v in s.knights.keys)
        if (MatchEngine.legalPromote(s, v)) v,
    ],
    _Move.knightMove =>
      selectedKnight == null
          ? [
              for (final v in s.knights.keys)
                if (s.knights[v]!.owner == s.active &&
                    s.knights[v]!.active &&
                    s.knights[v]!.actedTurn != s.turnSerial &&
                    MatchEngine.legalKnightDestinations(s, v).isNotEmpty)
                  v,
            ]
          : MatchEngine.legalKnightDestinations(s, selectedKnight!),
    _Move.bandit => [
      for (var i = 0; i < s.board.tiles.length; i++)
        if (i != s.banditTile) i,
    ],
    _Move.inspect => <int>[],
  };

  String targetDescription(int id) {
    String terrain(List<int> tiles) => tiles
        .map(
          (t) =>
              '${terrainLabel(s.board.tiles[t].land)} ${s.board.tiles[t].productionNumber ?? 'unnumbered'}',
        )
        .join(', ');
    if (move == _Move.bandit) {
      final tile = s.board.tiles[id];
      return 'Hex ${id + 1}: ${terrainLabel(tile.land)}, ${tile.productionNumber ?? 'no number'}';
    }
    if (move == _Move.road) {
      final edge = s.topology.edges[id];
      return 'Road ${id + 1}: junction ${edge.a + 1} to ${edge.b + 1}, ${terrain(edge.tiles)}';
    }
    return 'Junction ${id + 1}: ${terrain(s.topology.vertices[id].tiles)}';
  }

  Future<void> chooseTarget() async {
    final options = availableTargets;
    final boardSize = _boardSize;
    if (options.isEmpty || boardSize == null) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: !isCompactLandscape(context),
      builder: (context) => SafeArea(
        child: SizedBox(
          // Use most of the available landscape height while keeping every
          // board target accessible through the scrollable list.
          height: math.min(
            MediaQuery.sizeOf(context).height *
                (isCompactLandscape(context)
                    ? .94
                    : MediaQuery.textScalerOf(context).scale(1) > 1.2
                    ? .88
                    : .82),
            math.max(
              isCompactLandscape(context) ? 125 : 190,
              (isCompactLandscape(context) ? 38 : 62) +
                  options.length * (isCompactLandscape(context) ? 42.0 : 52.0),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isCompactLandscape(context) ? 2 : 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Choose legal board target',
                      style: isCompactLandscape(context)
                          ? Theme.of(context).textTheme.titleSmall
                          : Theme.of(context).textTheme.titleLarge,
                    ),
                    if (options.length > 4)
                      Text(
                        'Scroll to browse all ${options.length} targets',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: options.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(targetDescription(options[index])),
                    minVerticalPadding: 5,
                    dense: true,
                    onTap: () => Navigator.pop(context, options[index]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final geometry = BoardGeometry(boardSize);
    final Offset position;
    if (move == _Move.bandit) {
      position = geometry.tile(s.board.tiles[selected].position);
    } else if (move == _Move.road) {
      final edge = s.topology.edges[selected];
      position =
          (geometry.vertex(s.topology.vertices[edge.a]) +
              geometry.vertex(s.topology.vertices[edge.b])) /
          2;
    } else {
      position = geometry.vertex(s.topology.vertices[selected]);
    }
    await tapBoard(position, boardSize);
  }

  Future<void> _resourceTrade(Resource resource) =>
      _openTrade(_TradeKind.bank, initialGive: resource, fromTray: true);

  Future<void> exchange() => _openTrade(_TradeKind.bank);

  Future<void> offer([TradeProposal? counter]) =>
      _openTrade(_TradeKind.player, counter: counter);

  Future<void> _openTrade(
    _TradeKind kind, {
    TradeProposal? counter,
    Resource? initialGive,
    bool fromTray = false,
    _TradeDraft? draft,
  }) async {
    if ((widget.observing && counter == null) ||
        (s.active != viewerSeat && counter == null) ||
        s.phase != MatchPhase.actions ||
        s.tactical != null) {
      return;
    }
    setState(() => _tradeComposerOpen = true);
    _minimizedTradeComposer = null;
    final mobileTrade = MediaQuery.sizeOf(context).width < 900;
    final event = await showDialog<MatchEvent>(
      context: context,
      barrierColor: mobileTrade || fromTray ? Colors.black38 : null,
      builder: (_) => StatefulBuilder(
        builder: (context, updateKind) {
          return Dialog(
            // Fill the mobile viewport above the bottom resource tray.
            insetPadding: mobileTrade
                ? const EdgeInsets.fromLTRB(4, 4, 4, 64)
                : fromTray
                ? const EdgeInsets.fromLTRB(12, 8, 12, 72)
                : const EdgeInsets.all(12),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: mobileTrade ? double.infinity : 660,
              height: mobileTrade
                  ? MediaQuery.sizeOf(context).height
                  : MediaQuery.sizeOf(context).height * (fromTray ? .75 : .9),
              child: _TradeComposer(
                state: counter == null ? s : s.copyWith(active: viewerSeat),
                kind: kind,
                counter: counter,
                initialGive: initialGive,
                draft: draft,
                onMinimize: (saved) => setState(
                  () => _minimizedTradeComposer = (
                    kind: kind,
                    counter: counter,
                    initialGive: initialGive,
                    fromTray: fromTray,
                    draft: saved,
                  ),
                ),
                onKindSelected: counter == null
                    ? (value) => updateKind(() => kind = value)
                    : null,
              ),
            ),
          );
        },
      ),
    );
    if (mounted) {
      setState(() => _tradeComposerOpen = false);
      _scheduleIncomingTrade();
    }
    if (mounted &&
        event != null &&
        (!widget.observing || counter != null) &&
        (s.active == viewerSeat || counter != null) &&
        s.phase == MatchPhase.actions &&
        s.tactical == null) {
      send(event);
    }
  }

  /// An offer is announced once. Closing the dialog does not answer it:
  /// the same offer remains in the Trade tab without a floating reminder.
  void _scheduleIncomingTrade() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _incomingTradeOpen ||
          _tradeComposerOpen ||
          s.tactical != null ||
          s.phase != MatchPhase.actions ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      final incoming = s.offers
          .where(
            (offer) =>
                !_notifiedTradeOfferIds.contains(offer.id) &&
                offer.canRespond(viewerSeat) &&
                ((!widget.observing && s.active == viewerSeat) ||
                    (offer.proposer == s.active &&
                        (!widget.online || widget.tradeReplyAllowed))),
          )
          .firstOrNull;
      if (incoming == null) return;
      _notifiedTradeOfferIds.add(incoming.id);
      _incomingTradeOpen = true;
      _incomingDialogOfferId = incoming.id;
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          _incomingDialogContext = dialogContext;
          return Dialog(
            key: const ValueKey('incoming-trade-dialog'),
            insetPadding: const EdgeInsets.all(10),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: MediaQuery.sizeOf(dialogContext).height - 20,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Trade offer',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('dismiss-incoming-trade'),
                          tooltip: 'Dismiss',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                    TradeMarket(
                      state: s,
                      viewerSeat: viewerSeat,
                      computerSeats: widget.computerSeats,
                      onlyIncomingOfferId: incoming.id,
                      allowOffers: false,
                      allowCounters:
                          !widget.observing ||
                          widget.tradeReplyAllowed ||
                          !widget.online,
                      privateOpponentHands: widget.online,
                      onBank: () {},
                      onOffer: () {},
                      onCounter: (trade) {
                        Navigator.of(dialogContext).pop();
                        offer(trade);
                      },
                      onEvent: (event) {
                        Navigator.of(dialogContext).pop();
                        send(event);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ).whenComplete(() {
        _incomingTradeOpen = false;
        _incomingDialogContext = null;
        _incomingDialogOfferId = null;
        if (mounted) _scheduleIncomingTrade();
      });
    });
  }

  final _panelScroll = List.generate(4, (_) => ScrollController());

  bool get _compact => MediaQuery.sizeOf(context).height < 350;
  bool get _isLargeDesktop =>
      MediaQuery.sizeOf(context).width >= 1200 &&
      MediaQuery.sizeOf(context).height >= 550;

  int _tab = 0;
  // null: map; -1: full-screen actions.
  int? _mobilePage;

  void _openMobileCategory(int tab) {
    if (widget.observing && !(tab == 1 && widget.tradeReplyAllowed)) return;
    setState(() {
      _tab = tab;
      _mobilePage = -1;
    });
  }

  void _openMobileActions() {
    setState(() {
      _tab = 0;
      _mobilePage = -1;
    });
  }

  void _backMobile() => setState(() => _mobilePage = null);

  @override
  void dispose() {
    _turnClock?.cancel();
    _newCardTimer?.cancel();
    _roadController.dispose();
    _numberPulseController.dispose();
    _banditBlockController.dispose();
    _cardsTabController.dispose();
    _cityFallController.dispose();
    _longestRoadController.dispose();
    for (final controller in _panelScroll) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSeat =
        oldWidget.visibleSeat ??
        oldWidget.viewingSeat ??
        oldWidget.state.actingSeat;
    if (oldWidget.state.seed != s.seed ||
        oldWidget.state.events.length > s.events.length ||
        oldSeat != viewerSeat) {
      _notifiedTradeOfferIds.clear();
    }
    if (_incomingDialogOfferId != null &&
        !s.offers.any(
          (offer) =>
              offer.id == _incomingDialogOfferId &&
              offer.canRespond(viewerSeat),
        )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final dialogContext = _incomingDialogContext;
        if (dialogContext != null &&
            dialogContext.mounted &&
            (ModalRoute.of(dialogContext)?.isCurrent ?? false)) {
          Navigator.of(dialogContext).pop();
        }
      });
    }
    if (!oldWidget.state.pendingDiscards.containsKey(viewerSeat) &&
        s.pendingDiscards.containsKey(viewerSeat)) {
      _discardSecondsLeft = 45;
      _discardSelection.clear();
      _discardMinimized = false;
      _discardTimeoutSent = false;
    }
    if (!s.pendingDiscards.containsKey(viewerSeat)) {
      _discardSelection.clear();
      _discardMinimized = false;
      _discardTimeoutSent = false;
    }
    if (oldWidget.state.active != s.active ||
        (oldWidget.state.pendingDiscards.containsKey(viewerSeat) &&
            !s.pendingDiscards.containsKey(viewerSeat))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !(ModalRoute.of(context)?.isCurrent ?? true)) {
          Navigator.of(context)
              .popUntil((route) => route == ModalRoute.of(context));
        }
        if (mounted) _scheduleIncomingTrade();
      });
    } else {
      _scheduleIncomingTrade();
    }
    final previousSeat =
        oldWidget.visibleSeat ??
        oldWidget.viewingSeat ??
        oldWidget.state.active;
    if (s.seed == oldWidget.state.seed && previousSeat == viewerSeat) {
      // Compare copies, so receiving a card also registers when another card
      // was played or discarded in the same update.
      final previousCards = oldWidget.state.players[previousSeat].cards
          .toList();
      final gainedCards = s.players[viewerSeat].cards.where((card) {
        final index = previousCards.indexWhere(
          (previous) =>
              previous.track == card.track && previous.index == card.index,
        );
        if (index < 0) return true;
        previousCards.removeAt(index);
        return false;
      }).toList();
      if (gainedCards.isNotEmpty) {
        _unseenCard = _tab != 2;
        _newCardNotice = gainedCards
            .map((card) => card.definition.name)
            .join(', ');
        _newCardTimer?.cancel();
        _newCardTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _newCardNotice = null);
        });
        if (!MediaQuery.disableAnimationsOf(context)) {
          _cardsTabController.forward(from: 0);
        }
      }
    } else {
      _cardsTabController.value = 1;
    }
    if (s.seed != oldWidget.state.seed ||
        s.events.length < oldWidget.state.events.length) {
      _longestRoadWinner = null;
      _longestRoadRoute = const [];
      _longestRoadController.reset();
      _dismissedHintContext = null;
      _unseenCard = false;
      _newCardNotice = null;
      _newCardTimer?.cancel();
      _mapCard = null;
      _mapCardOptions = const [];
    }
    if (s.phase != oldWidget.state.phase ||
        (s.phase == MatchPhase.finished && s.seed != oldWidget.state.seed)) {
      _endModalDismissed = false;
    }
    final rolled = s.events
        .skip(oldWidget.state.events.length)
        .any((event) => event is RollDice);
    if (rolled) {
      _rollingDice = s.events
          .skip(oldWidget.state.events.length)
          .whereType<RollDice>()
          .last;
      _diceAnimationSerial++;
    }
    if (rolled && !MediaQuery.disableAnimationsOf(context)) {
      _numberPulseController.forward(from: 0);
    }
    final blockedRobbery = s.events
        .skip(oldWidget.state.events.length)
        .any(
          (event) =>
              event is RespondTactical &&
              event.choice == TacticalChoice.intercept,
        );
    if ((rolled &&
            s.dice != null &&
            s.board.tiles[s.banditTile].productionNumber == s.dice) ||
        blockedRobbery) {
      _humiliatedBanditTile = s.banditTile;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _banditBlockController.forward(from: 0);
      }
    }
    // Animate roads built by either a human or a computer. No game-state
    // changes are needed: this is purely visual, so replay stays deterministic.
    final additions = s.roads.keys.where(
      (id) => !oldWidget.state.roads.containsKey(id),
    );
    if (additions.isNotEmpty) {
      _animatedRoad = additions.last;
      final old = oldWidget.state;
      final edge = old.topology.edges[_animatedRoad!];
      final owner = s.roads[_animatedRoad!];
      bool connected(int vertex) =>
          old.sites[vertex]?.owner == owner ||
          old.topology.vertices[vertex].edges.any(
            (id) => old.roads[id] == owner,
          );
      // Reveal outwards from the settlement or existing road network, rather
      // than arbitrarily following the topology's edge ID orientation.
      _animatedRoadStart = old.pendingVillage == edge.b
          ? edge.b
          : old.pendingVillage == edge.a
          ? edge.a
          : connected(edge.b) && !connected(edge.a)
          ? edge.b
          : edge.a;
      _roadController.forward(from: 0);
    }
    if (s.seed == oldWidget.state.seed &&
        s.longestRoadHolder != null &&
        s.longestRoadHolder != oldWidget.state.longestRoadHolder) {
      _longestRoadWinner = s.longestRoadHolder;
      _longestRoadRoute = MatchEngine.longestRoadPath(s, s.longestRoadHolder!);
      if (!MediaQuery.disableAnimationsOf(context)) {
        _longestRoadController.forward(from: 0);
      } else {
        _longestRoadWinner = null;
      }
    }
    if (s.seed == oldWidget.state.seed &&
        s.invasions > oldWidget.state.invasions) {
      final fallenSites = oldWidget.state.sites.entries.where((site) {
        final after = s.sites[site.key];
        return after != null &&
            after.owner == site.value.owner &&
            after.structure.index < site.value.structure.index;
      }).toList();
      // When multiple cities collapse simultaneously, report the local
      // player's loss before an opponent's; do not hide their catastrophe.
      fallenSites.sort(
        (a, b) => (a.value.owner == viewerSeat ? 0 : 1).compareTo(
          b.value.owner == viewerSeat ? 0 : 1,
        ),
      );
      if (fallenSites.isNotEmpty) {
        final fallen = fallenSites.first.value;
        _fallenCityOwner = s.players[fallen.owner].id;
        _fallenCityVp = fallen.structure == Structure.capital ? 2 : 1;
        if (!MediaQuery.disableAnimationsOf(context)) {
          _cityFallController.forward(from: 0);
        } else {
          _cityFallController.value = .5;
        }
      }
    }
    if (oldWidget.state.turnSerial != s.turnSerial ||
        oldWidget.state.active != s.active ||
        oldWidget.state.actingSeat != s.actingSeat) {
      _secondsLeft = 90;
      _expiredEventCount = null;
    }
    if (oldWidget.state.events.length != s.events.length ||
        oldWidget.state.active != s.active) {
      _mapCard = null;
      _mapCardOptions = const [];
    }
    if (oldWidget.state.active != s.active ||
        oldWidget.state.phase != s.phase) {
      choice = _Move.inspect;
      selectedKnight = null;
    }
  }

  String get _instruction => s.tactical != null
      ? 'A response is pending'
      : switch (s.phase) {
          MatchPhase.setupVillage =>
            s.setupStep < s.players.length
                ? 'Place your village'
                : 'Place your town',
          MatchPhase.setupRoad => 'Connect your settlement',
          MatchPhase.roll => '',
          MatchPhase.bandit => 'Move the Bandit',
          MatchPhase.invasion => 'Defend the realm',
          MatchPhase.finished =>
            '${s.players[MatchEngine.winner(s) ?? s.active].id} wins!',
          MatchPhase.actions => switch (move) {
            _Move.inspect => 'Shape your realm',
            _Move.village => 'Place a village',
            _Move.road => 'Build a road',
            _Move.upgrade => 'Upgrade a settlement',
            _Move.fortify => 'Fortify a town',
            _Move.recruit => 'Recruit a Knight',
            _Move.activate => 'Activate a Knight',
            _Move.promote => 'Promote a Knight',
            _Move.knightMove =>
              selectedKnight == null
                  ? 'Select a Knight'
                  : 'Choose a destination',
            _Move.bandit => 'Move the Bandit',
          },
        };

  String get _hint => s.tactical != null
      ? 'Resolve this response to continue the turn'
      : switch (s.phase) {
          MatchPhase.setupVillage =>
            'Tap a glowing junction · first placements are free',
          MatchPhase.setupRoad =>
            'Tap a glowing edge beside your new settlement',
          MatchPhase.roll => '',
          MatchPhase.bandit => 'Tap another hex, then choose a neighbour',
          MatchPhase.invasion => 'Review the fleet and your shared defence',
          MatchPhase.finished => '15 Victory Points · a realm to remember',
          MatchPhase.actions => switch (move) {
            _Move.road =>
              '${_costLabel(MatchEngine.effectiveRoadCost(s))} · tap a glowing edge',
            _Move.village =>
              '${_costLabel(MatchEngine.villageCost)} · tap a glowing junction',
            _Move.inspect => 'Build, trade or play a card',
            _ => 'Tap a glowing target on the map',
          },
        };

  @override
  Widget build(BuildContext context) {
    _scheduleDiscardDialog();
    final phase = s.phase;
    final gameplayHint = _activeGameplayHint;
    final mobile = MediaQuery.sizeOf(context).width < 900;
    return PopScope(
      canPop: !mobile || _mobilePage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mobile && _mobilePage != null) _backMobile();
      },
      child: Material(
        color: const Color(0xff101e25),
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  if (!mobile || _mobilePage == null) _playerBar(),
                  Expanded(
                    child: LayoutBuilder(
                      key: _panelHintTarget,
                      builder: (context, bounds) {
                        if (mobile) return _mobileLayout(phase);
                        final desktop =
                            bounds.maxWidth >= 1200 && bounds.maxHeight >= 550;
                        final railWidth = desktop
                            ? (bounds.maxWidth * .25).clamp(320.0, 420.0)
                            : math.min(320.0, bounds.maxWidth * .48);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _map()),
                            SizedBox(
                              width: railWidth,
                              child: Material(
                                color: const Color(0xff182a31),
                                child: Column(
                                  children: [
                                    if (s.tactical == null || widget.observing)
                                      _tabs(),
                                    Expanded(
                                      child:
                                          s.tactical != null &&
                                              !widget.observing
                                          ? _TacticalPanel(
                                              state: s,
                                              onEvent: send,
                                              online: widget.online,
                                            )
                                          : Scrollbar(
                                              controller: _panelScroll[_tab],
                                              thumbVisibility: true,
                                              interactive: true,
                                              child: ListView(
                                                controller: _panelScroll[_tab],
                                                key: PageStorageKey(
                                                  'panel-$_tab',
                                                ),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: _compact ? 8 : 12,
                                                  vertical: _compact ? 4 : 12,
                                                ),
                                                children: [
                                                  _waitingStatus(),
                                                  ..._visiblePanelContents(
                                                    phase,
                                                  ),
                                                ],
                                              ),
                                            ),
                                    ),
                                    Visibility(
                                      visible:
                                          s.tactical == null &&
                                          !widget.observing &&
                                          s.phase != MatchPhase.finished,
                                      maintainSize: true,
                                      maintainAnimation: true,
                                      maintainState: true,
                                      child: _turnAction(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (!mobile || _mobilePage == null || _tradeComposerOpen)
                    _resourceTray(anchorHarvest: true),
                ],
              ),
            ),
            Positioned.fill(
              child: ResourceHarvest(
                state: s,
                seat: viewerSeat,
                anchors: _resourceAnchors,
                deferAnimation: _rollingDice != null,
              ),
            ),
            if (_isLargeDesktop)
              Positioned.fill(
                child: MatchActivity(
                  key: const ValueKey('centered-desktop-emotes'),
                  state: s,
                  viewerSeat: viewerSeat,
                  computerSeats: widget.computerSeats,
                  emotesOnly: true,
                  emote: widget.networkEmote ?? _emote,
                  emoteSerial: widget.online && widget.onEmote != null
                      ? widget.networkEmoteSerial
                      : _emoteSerial,
                  emoteSeat: widget.networkEmoteSeat,
                ),
              ),
            if (_discardMinimized && s.pendingDiscards.containsKey(viewerSeat))
              Positioned(
                top: MediaQuery.paddingOf(context).top + 106,
                right: 10,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('restore-discard'),
                  onPressed: () => setState(() => _discardMinimized = false),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text('Discard · ${_discardSecondsLeft}s'),
                ),
              ),
            if (_minimizedTradeComposer != null &&
                s.phase == MatchPhase.actions &&
                s.tactical == null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 198,
                right: 10,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('restore-trade-composer'),
                  onPressed: () {
                    final saved = _minimizedTradeComposer!;
                    setState(() => _minimizedTradeComposer = null);
                    _openTrade(
                      saved.kind,
                      counter: saved.counter,
                      initialGive: saved.initialGive,
                      fromTray: saved.fromTray,
                      draft: saved.draft,
                    );
                  },
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Resume trade'),
                ),
              ),
            if (!mobile || _mobilePage == null)
              Positioned(
                // The React control must never cover the mobile tabs.
                top: MediaQuery.paddingOf(context).top + 2,
                right: 1,
                child: _emoteButton(),
              ),
            if (_choosingCardTarget)
              Positioned(
                top: MediaQuery.paddingOf(context).top + (mobile ? 94 : 65),
                left: 12,
                right: 12,
                child: Center(
                  child: Card(
                    key: const ValueKey('choose-card-target-on-map'),
                    color: const Color(0xff584322),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: const BorderSide(
                        color: Color(0xffffe092),
                        width: 2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.place_rounded,
                            color: Color(0xffffe092),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              _mapCardTargetMessage,
                              maxLines: 2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('cancel-card-map-target'),
                            tooltip: 'Cancel card target',
                            onPressed: () => setState(() {
                              _mapCard = null;
                              _mapCardOptions = const [];
                            }),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_newCardNotice != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + (mobile ? 155 : 118),
                left: 16,
                right: 16,
                child: Center(
                  child: Material(
                    key: const ValueKey('card-received-banner'),
                    elevation: 12,
                    color: const Color(0xff60451d),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => setState(() {
                        _tab = 2;
                        _unseenCard = false;
                        if (mobile) _mobilePage = -1;
                        _newCardNotice = null;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              color: Color(0xffffe092),
                              size: 29,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'NEW STRATEGY CARD!',
                                    style: TextStyle(
                                      color: Color(0xffffe092),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    _newCardNotice!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Text(
                                    'Tap to view in Cards',
                                    style: TextStyle(
                                      color: Color(0xfff9db9a),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_unseenCard && mobile && _mobilePage == null)
              Positioned(
                bottom: 102,
                right: 12,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('new-card-shortcut'),
                  onPressed: () => setState(() {
                    _tab = 2;
                    _mobilePage = -1;
                    _unseenCard = false;
                  }),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('New card!'),
                ),
              ),
            if (_fallenCityOwner != null)
              Positioned.fill(child: IgnorePointer(child: _cityFallOverlay())),
            if (_longestRoadWinner != null)
              Positioned.fill(
                child: IgnorePointer(child: _longestRoadOverlay()),
              ),
            if (gameplayHint != null)
              Positioned.fill(
                child: BlockSemantics(
                  child: _gameplayHint(mobile, gameplayHint),
                ),
              ),
            if (s.phase == MatchPhase.finished && _endModalDismissed)
              Positioned(
                right: 16,
                top: 65,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('reopen-match-finale'),
                  onPressed: () => setState(() => _endModalDismissed = false),
                  icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                  label: const Text('Results'),
                ),
              ),
            if (s.phase == MatchPhase.finished && !_endModalDismissed)
              Positioned.fill(child: _finishOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _longestRoadOverlay() => AnimatedBuilder(
    animation: _longestRoadController,
    builder: (context, child) {
      final t = _longestRoadController.value;
      final opacity =
          (t < .16
                  ? t / .16
                  : t > .78
                  ? (1 - t) / .22
                  : 1.0)
              .clamp(0.0, 1.0);
      return Opacity(
        opacity: opacity,
        child: Align(
          alignment: const Alignment(0, -.45),
          child: Transform.scale(
            scale: .78 + .22 * Curves.elasticOut.transform(t.clamp(0.0, 1.0)),
            child: DecoratedBox(
              key: const ValueKey('longest-road-award-animation'),
              decoration: BoxDecoration(
                color: const Color(0xf5222b32),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xffffd680), width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x99000000), blurRadius: 24),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '🏆 LONGEST ROAD!',
                      style: TextStyle(
                        color: Color(0xffffde93),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${s.players[_longestRoadWinner!].id} · +2 VP',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _cityFallOverlay() => AnimatedBuilder(
    animation: _cityFallController,
    builder: (context, child) {
      final t = _cityFallController.value;
      final fade =
          (t < .15
                  ? t / .15
                  : t > .82
                  ? (1 - t) / .18
                  : 1.0)
              .clamp(0.0, 1.0);
      final shake = math.sin(t * 64) * (1 - t) * 13;
      final mine = _fallenCityOwner == s.players[viewerSeat].id;
      if (!mine) {
        return Opacity(
          opacity: fade,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 78, left: 12, right: 12),
              child: Transform.scale(
                scale:
                    .8 + .2 * Curves.easeOutBack.transform(t.clamp(0.0, 1.0)),
                child: DecoratedBox(
                  key: const ValueKey('rival-city-fall-animation'),
                  decoration: BoxDecoration(
                    color: const Color(0xff183931),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xff7fe4b8),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x99000000), blurRadius: 24),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '🎺  🤡  🎉',
                          style: TextStyle(fontSize: 29),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_fallenCityOwner!} lost a city!',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'The royal property market has collapsed.',
                          style: TextStyle(
                            color: Color(0xffbde7d4),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return Opacity(
        opacity: fade,
        child: Container(
          key: const ValueKey('city-fall-animation'),
          color: const Color(0xff3c0715).withValues(alpha: .72),
          child: Center(
            child: Transform.translate(
              offset: Offset(shake, math.sin(t * 22) * 5),
              child: Transform.scale(
                scale:
                    0.75 + .38 * Curves.elasticOut.transform(t.clamp(0.0, 1.0)),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: const Color(0xff1b101b),
                    border: Border.all(
                      color: const Color(0xffff6c43),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xffff4b22).withValues(alpha: .5),
                        blurRadius: 45,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('⚡  🔥  ⚡', style: TextStyle(fontSize: 38)),
                      Transform.rotate(
                        angle: math.sin(t * 38) * (1 - t) * .23,
                        child: const Icon(
                          Icons.castle_rounded,
                          color: Color(0xffff8861),
                          size: 84,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        mine
                            ? 'YOUR CITY HAS FALLEN!'
                            : "${_fallenCityOwner!.toUpperCase()}'S CITY HAS FALLEN!",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xffffd6a3),
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        mine
                            ? 'Your proud banners burn. The entire realm mocks your defeat.'
                            : 'The invaders grind another proud city into dust.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xffffb8aa),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '−$_fallenCityVp VICTORY ${_fallenCityVp == 1 ? 'POINT' : 'POINTS'}',
                        style: const TextStyle(
                          color: Color(0xffff6555),
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _finishOverlay() {
    final champion = MatchEngine.winner(s) ?? s.active;
    // Hot-seat games celebrate every human winner. In solo play, the winner
    // being an AI is defeat. Remote matches use the local viewing seat.
    final won = widget.online && widget.viewingSeat != null
        ? champion == widget.viewingSeat
        : widget.computerSeats.isEmpty ||
              !widget.computerSeats.contains(champion);
    return MatchEndModal(
      key: ValueKey('match-finale-${s.seed}'),
      state: s,
      winner: champion,
      victory: won,
      onReview: () => setState(() => _endModalDismissed = true),
      onHome: widget.onHome,
    );
  }

  Widget _mobileLayout(MatchPhase phase) {
    if (_mobilePage != null) {
      return Column(
        children: [
          if (s.tactical == null || widget.observing)
            Material(
              color: const Color(0xff182a31),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to map',
                    onPressed: _backMobile,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(child: _tabs()),
                ],
              ),
            ),
          if (s.tactical != null && !widget.observing) _backToBoardAction(),
          Expanded(child: _mobileActionHub()),
          // Keep inventory visible while trading, without burying it below
          // offer history in the scrolling panel.
          if (_tab == 1 && s.tactical == null && !_tradeComposerOpen)
            _resourceTray(),
        ],
      );
    }
    if (s.tactical != null && !widget.observing) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _openMobileActions,
              icon: const Icon(Icons.layers_outlined),
              label: const Text('Actions'),
            ),
          ),
          Expanded(
            child: _TacticalPanel(
              state: s,
              onEvent: send,
              online: widget.online,
            ),
          ),
        ],
      );
    }
    if (widget.observing) {
      return Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _map(mobileFullscreen: true)),
                if (widget.online &&
                    (widget.waitingMessage?.isNotEmpty ?? false))
                  Positioned(
                    right: 12,
                    bottom: 16,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xe014242b),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.waitingMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xffdce8e9),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  left: 12,
                  child: OutlinedButton.icon(
                    onPressed: _openMobileActions,
                    icon: const Icon(Icons.layers_outlined),
                    label: const Text('Actions'),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) => Stack(
              children: [
                Positioned.fill(child: _map(mobileFullscreen: true)),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        key: _actionsHintTarget,
                        width: math.min(128, bounds.maxWidth * .24),
                        child: OutlinedButton.icon(
                          key: const ValueKey('mobile-open-actions'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 42),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(fontSize: 13),
                            backgroundColor: const Color(0xf0182a31),
                            foregroundColor: const Color(0xffe5c183),
                          ),
                          onPressed: _openMobileActions,
                          icon: const Icon(Icons.layers_outlined),
                          label: const Text('Actions'),
                        ),
                      ),
                      if (s.phase != MatchPhase.finished)
                        SizedBox(
                          width: math.min(130, bounds.maxWidth * .26),
                          child: _turnButton(compact: true),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // End-turn is intentionally on the map only. A large persistent
        // button here obscures the build/trade/card actions on small phones.
      ],
    );
  }

  Widget _hintSetting({bool dismissPopup = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SwitchListTile(
        dense: isCompactLandscape(context),
        title: const Text('Gameplay hints'),
        subtitle: isCompactLandscape(context)
            ? null
            : const Text('Explain each mechanic the first time you use it'),
        value: _hintsEnabled,
        onChanged: _hintsLoaded
            ? (value) {
                if (dismissPopup) Navigator.of(context).pop();
                _setHintsEnabled(value);
              }
            : null,
      ),
      if (_seenHints.isNotEmpty)
        TextButton.icon(
          onPressed: () async {
            if (dismissPopup) Navigator.of(context).pop();
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('gameplay_hints_seen_v1');
            if (!mounted) return;
            setState(() {
              _seenHints.clear();
              _dismissedHintContext = null;
            });
          },
          icon: const Icon(Icons.replay, size: 18),
          label: const Text('Show first-time hints again'),
        ),
    ],
  );

  List<Widget> _matchOptions() => [
    if (widget.onLeaveRoom != null)
      ListTile(
        key: const ValueKey('match-leave-room-menu'),
        leading: const Icon(Icons.exit_to_app_outlined),
        title: const Text('Leave room'),
        onTap: () {
          Navigator.of(context).pop();
          widget.onLeaveRoom?.call();
        },
      ),
    _hintSetting(dismissPopup: true),
    if (widget.onSettings != null)
      ListTile(
        leading: const Icon(Icons.settings),
        title: const Text("Settings"),
        onTap: () async {
          Navigator.of(context).pop();
          await widget.onSettings?.call();
          if (mounted) await _loadHints();
        },
      ),
    if (widget.onRules != null)
      ListTile(
        leading: const Icon(Icons.menu_book),
        title: const Text('Rules'),
        onTap: () {
          Navigator.of(context).pop();
          widget.onRules?.call();
        },
      ),
    if (widget.onHome != null)
      ListTile(
        leading: const Icon(Icons.home_outlined),
        title: const Text('Home'),
        onTap: () {
          Navigator.of(context).pop();
          widget.onHome?.call();
        },
      ),
  ];

  Widget _mobileActionHub() => ListView(
    controller: _panelScroll[_tab],
    key: const ValueKey('mobile-action-hub'),
    padding:
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height
        ? const EdgeInsets.fromLTRB(10, 6, 10, 8)
        : const EdgeInsets.fromLTRB(16, 12, 16, 16),
    children: [
      // The countdown must remain visible while browsing action tabs, not
      // only on the player card when the board is showing.
      Visibility(
        visible: s.phase != MatchPhase.finished && !widget.observing,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              'Turn · ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 11, color: Color(0xffa8bfc0)),
            ),
          ),
        ),
      ),
      if (s.tactical != null && !widget.observing)
        SizedBox(
          height: 450,
          child: _TacticalPanel(state: s, onEvent: send, online: widget.online),
        )
      else ...[
        _waitingStatus(),
        if (_tab == 0 &&
            s.phase != MatchPhase.setupVillage &&
            s.phase != MatchPhase.setupRoad)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Choose a piece, then tap a highlighted spot on the map.',
              style: TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
            ),
          ),
        ..._visiblePanelContents(s.phase),
      ],
    ],
  );

  String? _emote;
  int _emoteSerial = 0;

  Widget _emoteButton() => PopupMenuButton<String>(
    tooltip: 'React',
    icon: const Text('🙂', style: TextStyle(fontSize: 22)),
    onSelected: (emoji) {
      if (widget.online && widget.onEmote != null) {
        widget.onEmote!(emoji);
      } else {
        setState(() {
          _emote = emoji;
          _emoteSerial++;
        });
      }
    },
    itemBuilder: (context) => [
      for (final emoji in ['👋', '😄', '😤', '😏', '👏', '🤝'])
        PopupMenuItem(value: emoji, child: GameEmoteIcon(emoji, size: 24)),
    ],
  );

  Widget _playerBar() => LayoutBuilder(
    builder: (context, bounds) {
      final winner = MatchEngine.winner(s);
      final size = MediaQuery.sizeOf(context);
      final portrait = size.height > size.width && bounds.maxWidth < 600;
      final height = portrait
          ? 104.0
          : math.max(
              bounds.maxWidth < 900
                  ? 44.0
                  : _compact
                  ? 48.0
                  : 52.0,
              MediaQuery.textScalerOf(context).scale(12) * 1.2 +
                  MediaQuery.textScalerOf(context).scale(10) * 1.2 +
                  18,
            );
      // Large accessibility text needs full-width cards rather than a
      // squeezed two-column grid. The portrait list can scroll vertically.
      final singleColumn =
          portrait &&
          (bounds.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(12) > 15);
      final width = portrait
          ? singleColumn
                ? bounds.maxWidth - 62 - (widget.onLeaveRoom != null ? 48 : 0)
                : (bounds.maxWidth -
                          68 -
                          (widget.onLeaveRoom != null ? 48 : 0)) /
                      2
          : math.max(
              124.0 * MediaQuery.textScalerOf(context).scale(12) / 12,
              (bounds.maxWidth - 50) / s.players.length - 6,
            );
      return Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(8, 3, 42, 3),
        decoration: const BoxDecoration(
          color: Color(0xff14242b),
          border: Border(bottom: BorderSide(color: Color(0xff34464a))),
        ),
        child: Row(
          children: [
            if (widget.onLeaveRoom != null)
              IconButton(
                key: const ValueKey('match-room-menu'),
                tooltip: 'Match menu',
                onPressed: _openPlayerOptions,
                icon: const Icon(Icons.menu_rounded),
              ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: portrait ? Axis.vertical : Axis.horizontal,
                child: Wrap(
                  runSpacing: portrait ? 2 : 0,
                  children: [
                    for (final i in [
                      viewerSeat,
                      for (var seat = 0; seat < s.players.length; seat++)
                        if (seat != viewerSeat) seat,
                    ])
                      Semantics(
                        label:
                            '${s.players[i].id}, ${MatchEngine.score(s, i)} of 15 Victory Points${i == winner
                                ? ', winner'
                                : i == s.active
                                ? ', active player'
                                : ''}',
                        child: Tooltip(
                          message: i == viewerSeat
                              ? 'Settings'
                              : '${MatchEngine.score(s, i)} VP',
                          child: InkWell(
                            onTap: i == viewerSeat ? _openPlayerOptions : null,
                            child: Container(
                              width: width,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: i == s.active
                                    ? seatColors[i].withValues(alpha: .13)
                                    : const Color(0xff1c2e35),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: i == s.active
                                      ? seatColors[i]
                                      : const Color(0xff30434a),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 29,
                                        height: 40,
                                        child: Stack(
                                          children: [
                                            Align(
                                              alignment: Alignment.center,
                                              child: Icon(
                                                i == s.active
                                                    ? Icons.flag_rounded
                                                    : Icons.shield_outlined,
                                                size: 20,
                                                color: seatColors[i],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              s.players[i].id,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                height: 1.2,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              i == winner
                                                  ? 'Winner'
                                                  : i == s.active
                                                  ? 'Turn · ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}${s.longestRoadHolder == i ? ' · Road +2' : ''}'
                                                  : s.longestRoadHolder == i
                                                  ? 'Longest road · +2 VP'
                                                  : 'Realm ${i + 1}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                height: 1.2,
                                                color: i == s.active
                                                    ? seatColors[i]
                                                    : const Color(0xffa6b6ba),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width:
                                            MediaQuery.textScalerOf(context)
                                                .scale(20) *
                                            1.4,
                                        child: Text(
                                          '${MatchEngine.score(s, i)}',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: seatColors[i],
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const Text(
                                        ' /15',
                                        style: TextStyle(
                                          fontSize: 10,
                                          height: 1.2,
                                          color: Color(0xffa6b6ba),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Positioned.fill(
                                    child: MatchActivity(
                                      key: ValueKey('activity-seat-$i'),
                                      state: s,
                                      viewerSeat: viewerSeat,
                                      targetSeat: i,
                                      showEmotes: !_isLargeDesktop,
                                      computerSeats: widget.computerSeats,
                                      emote: widget.networkEmote ?? _emote,
                                      emoteSerial:
                                          widget.online &&
                                              widget.onEmote != null
                                          ? widget.networkEmoteSerial
                                          : _emoteSerial,
                                      emoteSeat: widget.networkEmoteSeat,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  void _openPlayerOptions() {
    if (isCompactLandscape(context)) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(6),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 690,
            height: math.min(
              MediaQuery.sizeOf(dialogContext).height - 12,
              widget.onLeaveRoom == null ? 228 : 270,
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Return to board',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Text(
                        'Match options',
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListTileTheme(
                    data: const ListTileThemeData(
                      dense: true,
                      minVerticalPadding: 0,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ListView(
                            children: [_hintSetting(dismissPopup: true)],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final option in _matchOptions())
                                if (option is ListTile) option,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _matchOptions(),
          ),
        ),
      ),
    );
  }

  double get _instructionHeight => math.max(
    50,
    MediaQuery.textScalerOf(context).scale(15) * 1.2 +
        MediaQuery.textScalerOf(context).scale(11) * 1.2 +
        12,
  );

  Offset _eventAnchor(Size size) {
    final g = BoardGeometry(size);
    if (s.events.isEmpty) return g.center;
    final event = s.events.last;
    int? vertex;
    int? tile;
    if (event is PlaceVillage) vertex = event.vertex;
    if (event is UpgradeSite) vertex = event.vertex;
    if (event is FortifyTown) vertex = event.vertex;
    if (event is RecruitKnight) vertex = event.vertex;
    if (event is ActivateKnight) vertex = event.vertex;
    if (event is PromoteKnight) vertex = event.vertex;
    if (event is MoveKnight) vertex = event.to;
    if (event is MoveBandit) tile = event.tile;
    if (event is PlayStrategyCard) {
      vertex = event.vertex;
      tile = event.tile;
    }
    if (vertex != null && vertex >= 0 && vertex < s.topology.vertices.length) {
      return g.vertex(s.topology.vertices[vertex]);
    }
    if (tile != null && tile >= 0 && tile < s.board.tiles.length) {
      return g.tile(s.board.tiles[tile].position);
    }
    if (event is PlaceRoad &&
        event.edge >= 0 &&
        event.edge < s.topology.edges.length) {
      final edge = s.topology.edges[event.edge];
      return (g.vertex(s.topology.vertices[edge.a]) +
              g.vertex(s.topology.vertices[edge.b])) /
          2;
    }
    return g.center;
  }

  Widget _map({bool mobileFullscreen = false}) => Stack(
    key: _boardHintTarget,
    children: [
      Positioned.fill(
        child: LayoutBuilder(
          builder: (context, box) {
            // Keep the instruction strip outside the interactive map coordinates.
            final size = Size(
              box.maxWidth,
              math.max(
                1,
                box.maxHeight - (mobileFullscreen ? 0 : _instructionHeight),
              ),
            );
            _boardSize = size;
            final hover = _hoverPosition == null
                ? null
                : _boardHover(_hoverPosition!, size);
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: ClipRect(
                  child: Semantics(
                    key: const ValueKey('realm-map'),
                    label: 'Realm map. $_instruction. $_hint',
                    child: MouseRegion(
                      cursor: hover == null
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      onHover: (event) =>
                          setState(() => _hoverPosition = event.localPosition),
                      onExit: (_) => setState(() => _hoverPosition = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: s.tactical == null && !widget.observing
                            ? (details) => tapBoard(details.localPosition, size)
                            : null,
                        child: CustomPaint(
                          painter: _Painter(
                            s,
                            widget.observing || s.tactical != null
                                ? _Move.inspect
                                : move,
                            selectedKnight,
                            showTargets:
                                !widget.observing &&
                                viewerSeat == s.actingSeat &&
                                s.tactical == null,
                            hoverBuilds: _hoverPosition != null,
                            hoveredRoad:
                                _hoverPosition != null &&
                                    !widget.observing &&
                                    viewerSeat == s.actingSeat &&
                                    s.tactical == null &&
                                    (move == _Move.road ||
                                        (move == _Move.inspect &&
                                            s.phase == MatchPhase.actions))
                                ? _roadNear(
                                    _hoverPosition!,
                                    BoardGeometry(size),
                                    MatchEngine.legalEdges(s),
                                  )
                                : null,
                            cardRoadTargets: _mapCardEdges,
                            cardVertexTargets: _mapCardVertices,
                            cardTileTargets: _mapCardTiles,
                            animatedRoad: _animatedRoad,
                            animatedRoadStart: _animatedRoadStart,
                            roadReveal: _roadReveal,
                            roadCelebration: _longestRoadController,
                            highlightedRoads: _longestRoadRoute,
                            numberPulse: _numberPulseController,
                            banditBlock: _banditBlockController,
                            humiliatedBanditTile: _humiliatedBanditTile,
                          ),
                          child: SizedBox.expand(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (hover != null)
                                  Positioned(
                                    left: (_hoverPosition!.dx + 16).clamp(
                                      8.0,
                                      math.max(8.0, size.width - 268),
                                    ),
                                    top: (_hoverPosition!.dy + 24).clamp(
                                      8.0,
                                      math.max(8.0, size.height - 100),
                                    ),
                                    child: IgnorePointer(
                                      child: Container(
                                        key: const ValueKey('board-hover-hint'),
                                        width: 250,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xff101e25),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xffd6bd80),
                                          ),
                                        ),
                                        child: Text(
                                          hover,
                                          style: const TextStyle(
                                            color: Color(0xfff5ead3),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                BoardEventEffects(
                                  eventIndex: s.events.length,
                                  event: s.events.isEmpty
                                      ? null
                                      : s.events.last,
                                  anchor: _eventAnchor(size),
                                ),
                                if (_rollingDice case final dice?)
                                  IgnorePointer(
                                    child: DiceRoll(
                                      key: ValueKey(_diceAnimationSerial),
                                      first: dice.first,
                                      second: dice.second,
                                      onComplete: () {
                                        if (mounted &&
                                            identical(_rollingDice, dice)) {
                                          setState(() => _rollingDice = null);
                                        }
                                      },
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
            );
          },
        ),
      ),
      // Show countdown / raid interval and defence / bandit strength.
      Positioned(
        top: 8,
        left: 10,
        child: IgnorePointer(
          child: ConstrainedBox(
            key: const ValueKey('raid-defense-hud'),
            constraints: BoxConstraints(
              minWidth: mobileFullscreen ? 0 : 145,
              maxWidth: mobileFullscreen ? 145 : 180,
            ),
            child: Container(
              key: mobileFullscreen
                  ? const ValueKey('mobile-raid-defense-hud')
                  : null,
              padding: mobileFullscreen
                  ? const EdgeInsets.symmetric(horizontal: 9, vertical: 5)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xf014242b),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xff365159)),
              ),
              child: Semantics(
                label:
                    'Raid defence. ${s.raidInterval - s.reaverPressure.clamp(0, s.raidInterval)} of ${s.raidInterval} rounds until attack. ${MatchEngine.defenceStrength(s) + s.invasionAid} defence versus ${MatchEngine.invasionStrength(s)} bandit strength.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Raid Defense',
                      style: TextStyle(
                        color: Color(0xffefd6a3),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Raid ${s.raidInterval - s.reaverPressure.clamp(0, s.raidInterval)} / ${s.raidInterval} rounds',
                      style: const TextStyle(fontSize: 11, height: 1.15),
                    ),
                    Text(
                      'Defence ${MatchEngine.defenceStrength(s) + s.invasionAid} / ${MatchEngine.invasionStrength(s)}',
                      style: const TextStyle(fontSize: 11, height: 1.15),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (s.dice != null)
        Positioned(
          top: 52,
          right: 12,
          child: Semantics(
            label: 'Last dice total ${s.dice}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xf014242b),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xff61716a)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.casino_outlined,
                    size: 18,
                    color: Color(0xffe5c183),
                  ),
                  Text(
                    '${s.dice}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xffefd6a3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (mobileFullscreen &&
          availableTargets.isNotEmpty &&
          s.tactical == null &&
          !widget.observing)
        Positioned(
          top: 48,
          right: 6,
          child: IconButton(
            tooltip: 'Choose target',
            onPressed: chooseTarget,
            icon: const Icon(Icons.format_list_numbered),
          ),
        ),
      if (mobileFullscreen && choice != _Move.inspect && phaseAllowsChoice)
        Positioned(
          top: 94,
          right: 6,
          child: IconButton(
            tooltip: 'Cancel selection',
            onPressed: () => setState(() {
              choice = _Move.inspect;
              selectedKnight = null;
            }),
            icon: const Icon(Icons.close),
          ),
        ),
      if (!mobileFullscreen)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _instructionHeight,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
            decoration: const BoxDecoration(
              color: Color(0xff14242b),
              border: Border(top: BorderSide(color: Color(0xff34464a))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _instruction,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Color(0xffefd6a3),
                        ),
                      ),
                      Text(
                        _hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: Color(0xffabbfc2),
                        ),
                      ),
                    ],
                  ),
                ),
                if (availableTargets.isNotEmpty &&
                    s.tactical == null &&
                    !widget.observing)
                  IconButton(
                    tooltip: 'Choose target',
                    onPressed: chooseTarget,
                    icon: const Icon(Icons.format_list_numbered),
                  ),
                if (choice != _Move.inspect && phaseAllowsChoice)
                  IconButton(
                    tooltip: 'Cancel selection',
                    onPressed: () => setState(() {
                      choice = _Move.inspect;
                      selectedKnight = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
        ),
    ],
  );

  bool get phaseAllowsChoice => s.phase == MatchPhase.actions;

  double get _cardsTabPulse => _cardsTabController.isAnimating
      ? math.sin(_cardsTabController.value * math.pi * 3).abs()
      : 0;

  Widget _tabs() => AnimatedBuilder(
    animation: _cardsTabController,
    builder: (context, _) => Row(
      children: [
        for (final (index, icon, label) in [
          (0, Icons.construction_rounded, 'Build'),
          (1, Icons.swap_horiz_rounded, 'Trade'),
          (2, Icons.style_outlined, 'Cards'),
          (3, Icons.castle_outlined, 'Realm'),
        ])
          Expanded(
            child: Tooltip(
              key: index == 3 ? _realmHintTarget : _tabHintTargets[index],
              message: label,
              child: InkWell(
                onTap:
                    MediaQuery.sizeOf(context).width < 900 &&
                        widget.observing &&
                        !(index == 1 && widget.tradeReplyAllowed)
                    ? null
                    : () {
                        setState(() {
                          _tab = index;
                          if (index == 2) _unseenCard = false;
                          if (index != 0) {
                            choice = _Move.inspect;
                            selectedKnight = null;
                          }
                        });
                      },
                child: Container(
                  constraints: BoxConstraints(
                    minHeight:
                        isCompactLandscape(context) &&
                            MediaQuery.sizeOf(context).width < 900
                        ? 44
                        : _compact
                        ? 48
                        : 54,
                  ),
                  decoration: BoxDecoration(
                    color: index == 2
                        ? Color.lerp(
                            _tab == index
                                ? const Color(0xff2c4145)
                                : Colors.transparent,
                            const Color(0xff786039),
                            _cardsTabPulse * 0.7,
                          )
                        : _tab == index
                        ? const Color(0xff2c4145)
                        : null,
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: _tab == index
                            ? const Color(0xffe5c183)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(0, index == 2 ? -3 * _cardsTabPulse : 0),
                        child: Transform.scale(
                          key: index == 2
                              ? const ValueKey('cards-tab-pulse')
                              : null,
                          scale: index == 2 ? 1 + 0.2 * _cardsTabPulse : 1,
                          child: Icon(
                            icon,
                            size: 20,
                            color:
                                _tab == index ||
                                    (index == 2 &&
                                        _cardsTabController.isAnimating)
                                ? const Color(0xffefd6a3)
                                : const Color(0xffa6b6ba),
                          ),
                        ),
                      ),
                      if (index == 2 && _unseenCard)
                        Text(
                          'NEW CARD',
                          key: const ValueKey('new-card-indicator'),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Color.lerp(
                              const Color(0xffffdb7d),
                              Colors.white,
                              _cardsTabPulse,
                            ),
                          ),
                        ),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color: _tab == index
                              ? const Color(0xffefd6a3)
                              : const Color(0xffa6b6ba),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Color(0xffefd6a3),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
        ),
      ],
    ),
  );

  Widget _buildAction(
    _Move action,
    IconData icon,
    String name,
    String cost,
    bool enabled,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Tooltip(
      message: action == _Move.village && MatchEngine.legalVertices(s).isEmpty
          ? 'Extend a road first'
          : '$name · $cost',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size.fromHeight(52),
          alignment: Alignment.centerLeft,
          backgroundColor: choice == action
              ? const Color(0xff354e4b)
              : const Color(0xff20343c),
          side: BorderSide(
            color: choice == action
                ? const Color(0xffe5c183)
                : const Color(0xff40565b),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed:
            enabled &&
                phaseAllowsChoice &&
                !widget.observing &&
                s.tactical == null
            ? () => setState(() {
                choice = action;
                selectedKnight = null;
                _mobilePage = null;
              })
            : null,
        child: Row(
          children: [
            Icon(icon, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  // Measure every changing cost at this width and text scale.
                  // Discounts and rebuilding must not move subsequent actions.
                  Stack(
                    children: [
                      for (final label in {
                        cost,
                        if (action == _Move.road)
                          _costLabel(MatchEngine.roadCost),
                        if (action == _Move.recruit)
                          _costLabel(MatchEngine.recruitCost),
                        if (action == _Move.upgrade)
                          'Town: ${_costLabel(MatchEngine.townCost)}\n'
                              'Capital: ${_costLabel(MatchEngine.capitalCost)}\n'
                              'Rebuild: ${_costLabel(MatchEngine.rebuildCost)}',
                      })
                        Visibility(
                          visible: label == cost,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xffabbfc2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Visibility(
              visible: choice == action,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: const Icon(Icons.check_circle_outline, size: 20),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _backToBoardAction() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _mobilePage = null),
        icon: const Icon(Icons.map_outlined),
        label: const Text('Return to board'),
      ),
    ),
  );

  Widget _waitingStatus() {
    if (!widget.online) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.observing ? 'Waiting for players' : 'Your turn',
            style: const TextStyle(color: Color(0xffe5c183)),
          ),
          Text(
            s.players[s.tactical?.responder ?? s.active].id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            widget.waitingMessage ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  List<Widget> _visiblePanelContents(MatchPhase phase) {
    final contents = _panelContents(
      widget.observing ? MatchPhase.actions : phase,
      selectedTab: _tab,
    );
    // An offer can be answered outside your turn, but this must not expose
    // building, dice, End turn, bank trades or other turn-owner actions.
    if (!widget.observing || (_tab == 1 && widget.tradeReplyAllowed)) {
      return contents;
    }
    return [
      for (final child in contents)
        ExcludeFocus(child: AbsorbPointer(child: child)),
    ];
  }

  List<Widget> _panelContents(MatchPhase phase, {int? selectedTab}) {
    final tab = selectedTab ?? _tab;
    if (tab == 0) {
      return [
        if (phase != MatchPhase.actions && phase != MatchPhase.roll)
          _heading(
            _instruction,
            phase == MatchPhase.actions
                ? 'Choose a piece, then tap the map.'
                : phase == MatchPhase.setupVillage ||
                      phase == MatchPhase.setupRoad
                ? 'Place your starting pieces to begin.'
                : _hint,
          ),
        if (phase == MatchPhase.setupVillage ||
            phase == MatchPhase.setupRoad) ...[
          Icon(
            phase == MatchPhase.setupVillage
                ? Icons.holiday_village_rounded
                : Icons.route_rounded,
            size: 48,
            color: seatColors[s.active],
          ),
          const SizedBox(height: 12),
          Text(
            phase == MatchPhase.setupVillage
                ? (s.setupStep < s.players.length
                      ? 'Village · free'
                      : 'Town · free')
                : 'Road · free',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Glowing marks show every legal placement. You can also choose a target from the list below the map.',
            style: TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
          ),
        ],
        if (phase != MatchPhase.setupVillage &&
            phase != MatchPhase.setupRoad) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAction(
                _Move.road,
                Icons.route,
                'Road',
                s.roads.values.where((seat) => seat == viewerSeat).length >=
                        MatchEngine.roadLimit
                    ? 'No roads left (${MatchEngine.roadLimit}/${MatchEngine.roadLimit} built)'
                    : '${_costLabel(MatchEngine.effectiveRoadCost(s))} · ${MatchEngine.roadLimit - s.roads.values.where((seat) => seat == viewerSeat).length} roads left',
                MatchEngine.legalEdges(s).isNotEmpty,
              ),
              _buildAction(
                _Move.village,
                Icons.holiday_village,
                'Village',
                _costLabel(MatchEngine.villageCost),
                MatchEngine.legalVertices(s).isNotEmpty,
              ),
              _buildAction(
                _Move.upgrade,
                Icons.location_city,
                'Upgrade',
                _upgradeCostLabel(),
                MatchEngine.legalUpgrades(s).isNotEmpty,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAction(
                _Move.fortify,
                Icons.shield_outlined,
                'Fortify',
                _costLabel(MatchEngine.fortCost),
                s.sites.keys.any((v) => MatchEngine.legalFort(s, v)),
              ),
              _buildAction(
                _Move.recruit,
                Icons.person_add_alt,
                'Recruit Knight',
                _costLabel(
                  s.current.level(StrategyDeck.governance) >= 4
                      ? {Resource.wool: 1}
                      : MatchEngine.recruitCost,
                ),
                List.generate(
                  s.topology.vertices.length,
                  (v) => v,
                ).any((v) => MatchEngine.legalRecruit(s, v)),
              ),
              _buildAction(
                _Move.activate,
                Icons.bolt,
                'Activate Knight',
                _costLabel(MatchEngine.activateCost),
                s.knights.keys.any((v) => MatchEngine.legalActivate(s, v)),
              ),
              _buildAction(
                _Move.promote,
                Icons.upgrade,
                'Upgrade Knight',
                'Sentinel → Warden: ${_costLabel(MatchEngine.promotionCost(KnightRank.sentinel))}\nWarden → Champion: ${_costLabel(MatchEngine.promotionCost(KnightRank.warden))}',
                s.knights.keys.any((v) => MatchEngine.legalPromote(s, v)),
              ),
              _buildAction(
                _Move.knightMove,
                Icons.open_with,
                'Move Knight',
                'Free · active Knight, once per turn',
                s.knights.keys.any(
                  (v) =>
                      s.knights[v]!.owner == s.active &&
                      MatchEngine.legalKnightDestinations(s, v).isNotEmpty,
                ),
              ),
            ],
          ),
        ],
        if (phase == MatchPhase.invasion)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InvasionMeter(
                    state: s,
                    compact: MediaQuery.sizeOf(context).width < 900,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Expected: ${MatchEngine.invasionForecast(s)}',
                    maxLines: MediaQuery.sizeOf(context).width < 900 ? 2 : null,
                    overflow: MediaQuery.sizeOf(context).width < 900
                        ? TextOverflow.ellipsis
                        : null,
                  ),
                  if (MediaQuery.sizeOf(context).width >= 900)
                    const Text(
                      'Active Knights and Fortifications defend the realm.',
                    ),
                ],
              ),
            ),
          ),

        if (phase == MatchPhase.bandit)
          const Text(
            'Choose a different hex. Any theft and response will be resolved before building.',
            style: TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
          ),
      ];
    }
    if (tab == 1) {
      return [
        TradeMarket(
          state: s,
          computerSeats: widget.computerSeats,
          allowOffers: !widget.observing,
          allowCounters: !widget.observing || widget.tradeReplyAllowed,
          privateOpponentHands: widget.online,
          onBank: exchange,
          onOffer: offer,
          onCounter: offer,
          onEvent: send,
          viewerSeat: viewerSeat,
          onReturnToBoard: _mobilePage == null
              ? null
              : () => setState(() => _mobilePage = null),
        ),
        const SizedBox(height: 8),
        const Text(
          "Paper funds Innovation upgrades; cloth funds Commerce; coin funds Governance.",
          style: TextStyle(color: Color(0xffbac9cc), fontSize: 12),
        ),
      ];
    }
    if (tab == 2) {
      if (phase == MatchPhase.roll && MediaQuery.sizeOf(context).width < 900) {
        return [
          const Text('Roll the dice before playing your strategy cards.'),
        ];
      }
      return [
        StrategyHand(
          allowActions: !widget.observing && s.active == viewerSeat,
          state: s.active == viewerSeat ? s : s.copyWith(active: viewerSeat),
          onEvent: send,
          onChooseOnMap: _chooseCardTarget,
          onOpenRealm: _mobilePage == null
              ? null
              : () => _openMobileCategory(3),
          onlineOptions: widget.online
              ? (widget.onlineView?['options'] as Map?)
              : null,
        ),
      ];
    }
    return [
      _heading('Your realm', 'Develop Towns to unlock advanced goods.'),
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          'Paper (${s.players[viewerSeat].stores[Resource.paper] ?? 0}) · '
          'Cloth (${s.players[viewerSeat].stores[Resource.cloth] ?? 0}) · '
          'Coin (${s.players[viewerSeat].stores[Resource.coin] ?? 0})  —  '
          '${s.sites.values.any((site) => site.owner == viewerSeat && site.structure != Structure.village) ? 'Choose a track below.' : 'Upgrade a village to a Town first (2 wheat · 3 ore).'}',
          style: const TextStyle(fontSize: 12, color: Color(0xffbac9cc)),
        ),
      ),
      if (s.players[viewerSeat].level(StrategyDeck.innovation) < 5)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const ValueKey('quick-innovation-development'),
            onPressed:
                !widget.observing &&
                    s.active == viewerSeat &&
                    MatchEngine.canDevelop(s, StrategyDeck.innovation)
                ? () => send(const DevelopTown(StrategyDeck.innovation))
                : null,
            icon: const Icon(Icons.auto_awesome_outlined, size: 17),
            label: Text(
              s.players[viewerSeat].level(StrategyDeck.innovation) == 0
                  ? 'Unlock paper production'
                  : (MatchEngine.developmentCost(
                              s,
                              StrategyDeck.innovation,
                              s.players[viewerSeat].level(
                                    StrategyDeck.innovation,
                                  ) +
                                  1,
                            )[Resource.paper] ??
                            0) >
                        0
                  ? 'Spend paper on Innovation'
                  : 'Upgrade Innovation',
            ),
          ),
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Town Developments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          for (final track in StrategyDeck.values)
            Builder(
              builder: (context) {
                final level = s.players[viewerSeat].level(track);
                final cost = level == 5
                    ? <Resource, int>{}
                    : MatchEngine.developmentCost(s, track, level + 1);
                final missing = cost.entries
                    .where(
                      (entry) =>
                          (s.players[viewerSeat].stores[entry.key] ?? 0) <
                          entry.value,
                    )
                    .map(
                      (entry) =>
                          '${entry.value - (s.players[viewerSeat].stores[entry.key] ?? 0)} ${entry.key.displayName}',
                    )
                    .join(', ');
                final ownsTown = s.sites.values.any(
                  (site) =>
                      site.owner == viewerSeat &&
                      site.structure != Structure.village,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Tooltip(
                    message: 'Realm upgrades',
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${track.name.toUpperCase()} · $level/5',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              level < 5
                                  ? 'Next: ${track.tiers[level]}'
                                  : 'Complete',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              level == 0
                                  ? 'Unlocks ${track.commodity.displayName} from Towns beside ${terrainLabel(track.sourceLand)}.'
                                  : 'Towns beside ${terrainLabel(track.sourceLand)} produce ${track.commodity.displayName} instead of one ${track.sourceLand.produces!.name}.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xffadc4c6),
                              ),
                            ),
                            if (level < 5) ...[
                              const SizedBox(height: 5),
                              Text(
                                'Cost: ${_costLabel(cost)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (!ownsTown)
                                const Text(
                                  'Build a Town first to unlock developments.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xffe5c183),
                                  ),
                                )
                              else if (missing.isNotEmpty)
                                Text(
                                  'Need: $missing',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xffe5c183),
                                  ),
                                ),
                            ],
                            const SizedBox(height: 6),
                            OutlinedButton(
                              onPressed:
                                  !widget.observing &&
                                      s.active == viewerSeat &&
                                      MatchEngine.canDevelop(s, track)
                                  ? () => send(DevelopTown(track))
                                  : null,
                              child: Text(
                                level == 5
                                    ? 'Max level'
                                    : 'Develop ${track.name}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      if (MediaQuery.sizeOf(context).width >= 900 && !widget.observing)
        _hintSetting(),
    ];
  }

  Widget _turnAction() => Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: _compact ? 2 : 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xff34464a))),
    ),
    child: SizedBox(width: double.infinity, child: _turnButton()),
  );

  Widget _turnButton({bool compact = false}) => Tooltip(
    message: s.phase == MatchPhase.actions ? 'End turn' : _instruction,
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: Size(0, compact ? 42 : 48),
        padding: compact ? const EdgeInsets.symmetric(horizontal: 10) : null,
        textStyle: compact ? const TextStyle(fontSize: 13) : null,
        disabledBackgroundColor: const Color(0xff425963),
        disabledForegroundColor: const Color(0xfff4eee2),
        backgroundColor: const Color(0xffe5c183),
        foregroundColor: const Color(0xff28271e),
      ),
      onPressed:
          widget.observing || (widget.online && s.actingSeat != viewerSeat)
          ? null
          : switch (s.phase) {
              MatchPhase.roll => () {
                final (a, b) = widget.online
                    ? (0, 0)
                    : MatchEngine.expectedDice(s);
                send(RollDice(a, b));
              },
              MatchPhase.actions => () => send(const EndTurn()),
              MatchPhase.invasion => () => send(const ResolveInvasion()),
              MatchPhase.setupVillage ||
              MatchPhase.setupRoad ||
              MatchPhase.bandit =>
                availableTargets.isNotEmpty ? chooseTarget : null,
              _ => null,
            },
      icon: Icon(
        s.phase == MatchPhase.roll
            ? Icons.casino_outlined
            : s.phase == MatchPhase.invasion
            ? Icons.shield_outlined
            : s.phase == MatchPhase.setupVillage ||
                  s.phase == MatchPhase.setupRoad ||
                  s.phase == MatchPhase.bandit
            ? Icons.format_list_numbered
            : Icons.check_circle_outline,
      ),
      label: Text(
        s.phase == MatchPhase.roll
            ? 'Roll dice'
            : s.phase == MatchPhase.invasion
            ? compact
                  ? 'Resolve'
                  : 'Resolve Invasion'
            : s.phase == MatchPhase.actions
            ? 'End turn'
            : s.phase == MatchPhase.setupVillage
            ? compact
                  ? 'Site'
                  : 'Choose site'
            : s.phase == MatchPhase.setupRoad
            ? compact
                  ? 'Road'
                  : 'Choose road'
            : s.phase == MatchPhase.bandit
            ? compact
                  ? 'Bandit'
                  : 'Move Bandit'
            : s.phase == MatchPhase.finished
            ? 'Done'
            : 'Choose on map',
        style: const TextStyle(
          fontFamily: 'NotoSans',
          color: Color(0xff172b33),
        ),
      ),
    ),
  );

  Widget _resourceTray({bool anchorHarvest = false}) {
    final tight = _compact || MediaQuery.sizeOf(context).width < 900;
    final horizontal = anchorHarvest && MediaQuery.sizeOf(context).width >= 900;
    return Container(
      height: math.max(
        horizontal ? 58 : (tight ? 49 : 66),
        MediaQuery.textScalerOf(context).scale(tight ? 14 : 17) * 1.2 +
            (horizontal ? 0 : (tight ? 20 : 27)) +
            (tight ? 13 : 19),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: tight ? 4 : 6),
      decoration: const BoxDecoration(
        color: Color(0xff101e25),
        border: Border(top: BorderSide(color: Color(0xff34464a))),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.zero,
              child: Row(
                crossAxisAlignment: horizontal
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Choose resource icons',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => showResourceIconPicker(context),
                    icon: const Icon(
                      Icons.palette_outlined,
                      size: 20,
                      color: Color(0xffe5c183),
                    ),
                  ),
                  for (final r in Resource.values)
                    Expanded(
                      child: Tooltip(
                        message:
                            '${r.displayName}: ${inventoryOwner.stores[r] ?? 0}',
                        child: GestureDetector(
                          onTap:
                              s.phase == MatchPhase.actions && !widget.observing
                              ? () => _resourceTrade(r)
                              : null,
                          child: ResourceRewardPulse(
                            key: ValueKey('resource-tile-${r.name}'),
                            deferAnimation: _rollingDice != null,
                            anchor: anchorHarvest ? _resourceAnchors[r] : null,
                            count: inventoryOwner.stores[r] ?? 0,
                            seat: widget.viewingSeat ?? viewerSeat,
                            color: _goodColor(r),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: EdgeInsets.symmetric(
                                horizontal: horizontal ? 8 : 4,
                                vertical: horizontal ? 4 : 0,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xff20323a),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(
                                  top: BorderSide(
                                    color: _goodColor(r),
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Flex(
                                direction: horizontal
                                    ? Axis.horizontal
                                    : Axis.vertical,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (horizontal) ...[
                                    ResourceIcon(r, size: tight ? 20 : 27),
                                    const SizedBox(width: 8),
                                  ],
                                  if (horizontal)
                                    Expanded(
                                      child: Text(
                                        '${inventoryOwner.stores[r] ?? 0}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: tight ? 14 : 17,
                                          height: 1.2,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      '${inventoryOwner.stores[r] ?? 0}',
                                      style: TextStyle(
                                        fontSize: tight ? 14 : 17,
                                        height: 1.2,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  if (!horizontal)
                                    ResourceIcon(r, size: tight ? 20 : 27),
                                ],
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
        ],
      ),
    );
  }

  String _upgradeCostLabel() {
    final rebuilding = s.sites.entries.any(
      (entry) =>
          entry.value.owner == s.active &&
          entry.value.structure == Structure.village &&
          s.reaverScars.contains(entry.key),
    );
    return 'Town: ${_costLabel(MatchEngine.townCost)}\n'
        'Capital: ${_costLabel(MatchEngine.capitalCost)}'
        '${rebuilding ? '\nRebuild: ${_costLabel(MatchEngine.rebuildCost)}' : ''}';
  }

  String _costLabel(Map<Resource, int> cost) =>
      cost.entries.map((e) => '${e.value} ${e.key.displayName}').join(' · ');

  Color _goodColor(Resource r) => const [
    Color(0xff6f9e79),
    Color(0xffc78369),
    Color(0xffd7b968),
    Color(0xff9cbd95),
    Color(0xffa1b1c4),
    Color(0xffe3d8b7),
    Color(0xffbd9dca),
    Color(0xffe4c976),
  ][r.index];
}

enum _TradeKind { bank, player }

class _TradeDraft {
  const _TradeDraft({
    required this.target,
    required this.give,
    required this.take,
    required this.giveCount,
    required this.takeCount,
    required this.bankTimes,
    required this.extraGive,
    required this.extraTake,
  });
  final int target, giveCount, takeCount, bankTimes;
  final Resource give, take;
  final Map<Resource, int> extraGive, extraTake;
}

typedef _TradeResume = ({
  _TradeKind kind,
  TradeProposal? counter,
  Resource? initialGive,
  bool fromTray,
  _TradeDraft draft,
});

/// A focused dialog composes a trade while the table remains in place.
class _TradeComposer extends StatefulWidget {
  const _TradeComposer({
    required this.state,
    required this.kind,
    this.counter,
    this.initialGive,
    this.onKindSelected,
    this.draft,
    this.onMinimize,
  });
  final _TradeDraft? draft;
  final ValueChanged<_TradeDraft>? onMinimize;
  final MatchState state;
  final _TradeKind kind;
  final TradeProposal? counter;
  final Resource? initialGive;
  final ValueChanged<_TradeKind>? onKindSelected;

  @override
  State<_TradeComposer> createState() => _TradeComposerState();
}

class _TradeComposerState extends State<_TradeComposer> {
  late int target;
  late Resource give;
  late Resource take;
  Map<Resource, int> extraGive = {};
  Map<Resource, int> extraTake = {};
  late int giveCount;
  late int takeCount;
  int bankTimes = 1;
  _TradeDraft get currentDraft => _TradeDraft(
    target: target,
    give: give,
    take: take,
    giveCount: giveCount,
    takeCount: takeCount,
    bankTimes: bankTimes,
    extraGive: Map.of(extraGive),
    extraTake: Map.of(extraTake),
  );
  void _selectUsefulExchange() {
    final s = widget.state;
    final stores = s.current.stores;
    final fundedPlayers = s.players.toList();
    fundedPlayers[s.active] = s.current.copyWith(
      stores: {for (final good in Resource.values) good: 99},
    );
    final funded = s.copyWith(players: fundedPlayers);
    final costs = [
      if (MatchEngine.legalEdges(funded).isNotEmpty)
        MatchEngine.effectiveRoadCost(s),
      if (MatchEngine.legalVertices(funded).isNotEmpty) MatchEngine.villageCost,
      if (s.sites.values.any(
        (site) => site.owner == s.active && site.structure == Structure.village,
      ))
        MatchEngine.townCost,
      if (s.sites.values.any(
        (site) => site.owner == s.active && site.structure == Structure.town,
      ))
        MatchEngine.capitalCost,
      for (final track in StrategyDeck.values)
        if (s.current.level(track) < 5 &&
            s.sites.values.any(
              (site) =>
                  site.owner == s.active && site.structure != Structure.village,
            ))
          MatchEngine.developmentCost(s, track, s.current.level(track) + 1),
    ];
    int shortfall(Map<Resource, int> cost) => cost.entries.fold(
      0,
      (total, e) => total + (e.value - (stores[e.key] ?? 0)).clamp(0, e.value),
    );
    final incomplete = costs.where((cost) => shortfall(cost) > 0).toList()
      ..sort((a, b) {
        final missing = shortfall(a).compareTo(shortfall(b));
        if (missing != 0) return missing;
        // Prefer completing the larger build when both need the same goods.
        return b.values
            .fold<int>(0, (a, b) => a + b)
            .compareTo(a.values.fold<int>(0, (a, b) => a + b));
      });
    for (final cost in incomplete) {
      for (final wanted in Resource.values) {
        if ((stores[wanted] ?? 0) >= (cost[wanted] ?? 0) ||
            (s.bank[wanted] ?? 0) < 1) {
          continue;
        }
        for (final offered in Resource.values) {
          if (offered == wanted) continue;
          final rate = widget.kind == _TradeKind.bank
              ? MatchEngine.tradeRate(s, s.active, offered)
              : 1;
          final receipt =
              widget.kind == _TradeKind.bank &&
                  (s.current.level(StrategyDeck.commerce) >= 5 ||
                      (s.current.level(StrategyDeck.commerce) >= 3 &&
                          wanted == Resource.cloth))
              ? 2
              : 1;
          if ((stores[offered] ?? 0) < rate ||
              (s.bank[wanted] ?? 0) < receipt) {
            continue;
          }
          if (cost.entries.every(
            (e) =>
                (stores[e.key] ?? 0) -
                    (e.key == offered ? rate : 0) +
                    (e.key == wanted ? receipt : 0) >=
                e.value,
          )) {
            give = offered;
            take = wanted;
            takeCount = 1;
            return;
          }
        }
      }
    }
    // Otherwise seek goods with no production in the player's network.
    final produced = <Resource>{};
    for (final entry in s.sites.entries.where(
      (e) => e.value.owner == s.active,
    )) {
      for (final tile in s.topology.vertices[entry.key].tiles) {
        final resource = s.board.tiles[tile].land.produces;
        if (resource != null) produced.add(resource);
      }
    }
    final candidates =
        Resource.values.where((r) => r != give && (s.bank[r] ?? 0) > 0).toList()
          ..sort((a, b) {
            final production = (produced.contains(a) ? 1 : 0).compareTo(
              produced.contains(b) ? 1 : 0,
            );
            return production != 0
                ? production
                : (stores[a] ?? 0).compareTo(stores[b] ?? 0);
          });
    if (candidates.isNotEmpty) take = candidates.first;
  }

  @override
  void initState() {
    super.initState();
    final trade = widget.counter;
    final s = widget.state;
    target = trade?.proposer ?? -1;
    give = trade?.want ?? Resource.wood;
    take = trade?.give ?? Resource.wool;
    giveCount = trade?.wantCount ?? 1;
    takeCount = trade?.giveCount ?? 1;
    extraGive = Map.of(trade?.wants ?? {})..remove(give);
    extraTake = Map.of(trade?.gives ?? {})..remove(take);
    if (trade == null) {
      final payable = Resource.values.where(
        (good) =>
            (s.current.stores[good] ?? 0) >=
            (widget.kind == _TradeKind.bank
                ? MatchEngine.tradeRate(s, s.active, good)
                : 1),
      );
      if (payable.isNotEmpty) give = payable.first;
      _selectUsefulExchange();
      give = widget.initialGive ?? give;
      if (give == take) {
        take = Resource.values.firstWhere((good) => good != give);
      }
    }
    if (widget.draft case final saved?) {
      target = saved.target;
      give = saved.give;
      take = saved.take;
      giveCount = saved.giveCount;
      takeCount = saved.takeCount;
      bankTimes = saved.bankTimes;
      extraGive = Map.of(saved.extraGive);
      extraTake = Map.of(saved.extraTake);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final bank = widget.kind == _TradeKind.bank;
    final rate = MatchEngine.tradeRate(s, s.active, give);
    final commerce = s.current.level(StrategyDeck.commerce);
    final receipt = commerce >= 5 || (commerce >= 3 && take == Resource.cloth)
        ? 2
        : 1;
    final required = bank ? rate * bankTimes : giveCount;
    final available = s.current.stores[give] ?? 0;
    final bankAvailable = s.bank[take] ?? 0;
    final gives = {...extraGive, give: giveCount};
    final wants = {...extraTake, take: takeCount};
    final valid =
        (bank ||
            (canPayTrade(s.current.stores, gives) &&
                gives.keys.every((g) => !wants.containsKey(g)))) &&
        give != take &&
        available >= required &&
        (!bank || bankAvailable >= receipt * bankTimes) &&
        (bank || (giveCount > 0 && takeCount > 0 && target != s.active));
    final title = bank
        ? 'Bank exchange'
        : widget.counter == null
        ? 'Standing offer'
        : 'Counteroffer';
    final viewport = MediaQuery.sizeOf(context);
    final compactLandscape =
        viewport.width < 900 && viewport.width > viewport.height;
    return Scaffold(
      appBar: MediaQuery.sizeOf(context).width < 900
          ? null
          : AppBar(
              toolbarHeight: widget.onKindSelected == null ? 48 : 40,
              title: Text(title),
              leading: IconButton(
                tooltip: 'Close trade',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
              actions: [
                IconButton(
                  key: const ValueKey('minimize-trade-composer'),
                  tooltip: 'Minimize trade',
                  onPressed: () {
                    widget.onMinimize?.call(currentDraft);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.close_fullscreen),
                ),
              ],
            ),
      body: ListView(
        padding: compactLandscape
            ? const EdgeInsets.fromLTRB(10, 3, 10, 4)
            : const EdgeInsets.fromLTRB(16, 8, 16, 12),
        children: [
          if (compactLandscape)
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (widget.onKindSelected != null)
                  SizedBox(
                    width: 190,
                    child: SegmentedButton<_TradeKind>(
                      segments: const [
                        ButtonSegment(
                          value: _TradeKind.player,
                          label: Text('Player'),
                        ),
                        ButtonSegment(
                          value: _TradeKind.bank,
                          label: Text('Bank'),
                        ),
                      ],
                      selected: {widget.kind},
                      onSelectionChanged: (values) =>
                          widget.onKindSelected!(values.first),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                IconButton(
                  key: const ValueKey('mobile-minimize-trade'),
                  tooltip: 'Minimize trade',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    widget.onMinimize?.call(currentDraft);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.close_fullscreen, size: 19),
                ),
                IconButton(
                  tooltip: 'Close trade',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            )
          else if (MediaQuery.sizeOf(context).width < 900)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Minimize trade',
                  key: const ValueKey('mobile-minimize-trade'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    widget.onMinimize?.call(currentDraft);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.close_fullscreen, size: 19),
                ),
                IconButton(
                  tooltip: 'Close trade',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
          if (compactLandscape && widget.onKindSelected != null)
            SizedBox(
              height: 40,
              child: bank
                  ? Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Exchanges',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('bank-bundles-minus'),
                          tooltip: 'Fewer exchanges',
                          visualDensity: VisualDensity.compact,
                          onPressed: bankTimes > 1
                              ? () => setState(() => bankTimes--)
                              : null,
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 20,
                          ),
                        ),
                        Text(
                          '$bankTimes',
                          key: const ValueKey('bank-bundle-count'),
                        ),
                        IconButton(
                          key: const ValueKey('bank-bundles-plus'),
                          tooltip: 'More exchanges',
                          visualDensity: VisualDensity.compact,
                          onPressed:
                              bankTimes < 99 &&
                                  available >= rate * (bankTimes + 1) &&
                                  bankAvailable >= receipt * (bankTimes + 1)
                              ? () => setState(() => bankTimes++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const Text('Offer to', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<int>(
                            value: target,
                            isExpanded: true,
                            underline: const SizedBox.shrink(),
                            items: [
                              const DropdownMenuItem(
                                value: -1,
                                child: Text('Everyone'),
                              ),
                              for (var i = 0; i < s.players.length; i++)
                                if (i != s.active)
                                  DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                      'To ${s.players[i].id}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                            ],
                            onChanged: (seat) {
                              if (seat != null) setState(() => target = seat);
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          if (widget.onKindSelected != null && !compactLandscape) ...[
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<_TradeKind>(
                    segments: const [
                      ButtonSegment(
                        value: _TradeKind.player,
                        label: Text('Player'),
                      ),
                      ButtonSegment(
                        value: _TradeKind.bank,
                        label: Text('Bank'),
                      ),
                    ],
                    selected: {widget.kind},
                    onSelectionChanged: (values) =>
                        widget.onKindSelected!(values.first),
                    showSelectedIcon: false,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Visibility(
                    visible: !bank,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: DropdownButton<int>(
                      value: target,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem(
                          value: -1,
                          child: Text('To everyone'),
                        ),
                        for (var i = 0; i < s.players.length; i++)
                          if (i != s.active)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                'To ${s.players[i].id}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: (seat) {
                        if (seat != null) setState(() => target = seat);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else if (widget.onKindSelected == null) ...[
            Text(
              bank
                  ? 'Rate $rate:$receipt · Bank stock: $bankAvailable'
                  : target == -1
                  ? 'Everyone can accept. Private hands stay hidden.'
                  : 'Only ${s.players[target].id} can accept. Private hands stay hidden.',
              style: const TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
            ),
            const SizedBox(height: 11),
            if (!bank && widget.counter == null) ...[
              const Text(
                'OFFER TO',
                style: TextStyle(
                  color: Color(0xffe5c183),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 5,
                children: [
                  ChoiceChip(
                    key: const ValueKey('offer-target-everyone'),
                    showCheckmark: false,
                    selected: target == -1,
                    label: const Text('Everyone'),
                    onSelected: (_) => setState(() => target = -1),
                  ),
                  for (var i = 0; i < s.players.length; i++)
                    if (i != s.active)
                      ChoiceChip(
                        key: ValueKey('offer-target-$i'),
                        showCheckmark: false,
                        selected: target == i,
                        label: Text(s.players[i].id),
                        onSelected: (_) => setState(() => target = i),
                      ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
          if (widget.onKindSelected != null)
            SizedBox(
              height: compactLandscape ? 17 : 20,
              child: Text(
                bank
                    ? 'Rate $rate:$receipt · Bank stock: $bankAvailable'
                    : 'Offer goods to a player or everyone',
                key: const ValueKey('trade-summary-stable'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
              ),
            ),
          if (widget.onKindSelected != null && !compactLandscape)
            Visibility(
              visible: bank,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Exchanges',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('bank-bundles-minus'),
                    tooltip: 'Fewer exchanges',
                    onPressed: bankTimes > 1
                        ? () => setState(() => bankTimes--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$bankTimes', key: const ValueKey('bank-bundle-count')),
                  IconButton(
                    key: const ValueKey('bank-bundles-plus'),
                    tooltip: 'More exchanges',
                    onPressed:
                        bankTimes < 99 &&
                            available >= rate * (bankTimes + 1) &&
                            bankAvailable >= receipt * (bankTimes + 1)
                        ? () => setState(() => bankTimes++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final giveLeg = TradeLeg(
                title: 'YOU GIVE',
                hint: bank ? 'Pay the bank' : 'Give when accepted',
                compact: widget.onKindSelected != null || compactLandscape,
                resource: give,
                count: required,
                available: available,
                holdings: s.current.stores,
                showCount: !bank,
                onResource: (v) => setState(() {
                  extraGive.remove(v);
                  give = v;
                }),
                onCount: (v) => setState(() => giveCount = v),
              );
              final takeLeg = TradeLeg(
                title: 'YOU RECEIVE',
                hint: bank ? 'From the bank' : 'Request from your rival',
                compact: widget.onKindSelected != null || compactLandscape,
                resource: take,
                holdings: bank ? s.bank : null,
                count: bank ? receipt * bankTimes : takeCount,
                showCount: !bank,
                highlight: true,
                onResource: (v) => setState(() {
                  extraTake.remove(v);
                  take = v;
                }),
                onCount: (v) => setState(() => takeCount = v),
              );
              Widget bundleExtras(
                Widget leg,
                Map<Resource, int> extras,
                Resource primary,
              ) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  leg,
                  if (!bank) ...[
                    PopupMenuButton<Resource>(
                      tooltip: 'Add another resource',
                      onSelected: (good) => setState(() => extras[good] = 1),
                      itemBuilder: (_) => [
                        for (final good in Resource.values)
                          if (good != primary && !extras.containsKey(good))
                            PopupMenuItem(
                              value: good,
                              child: Text(good.displayName),
                            ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('+ Add another resource'),
                      ),
                    ),
                    for (final good in Resource.values)
                      if (good != primary && extras.containsKey(good))
                        Row(
                          children: [
                            Expanded(child: Text(good.displayName)),
                            IconButton(
                              tooltip: 'Remove ${good.displayName}',
                              onPressed: (extras[good] ?? 0) > 0
                                  ? () => setState(() {
                                      final count = extras[good]! - 1;
                                      if (count == 0) {
                                        extras.remove(good);
                                      } else {
                                        extras[good] = count;
                                      }
                                    })
                                  : null,
                              icon: const Icon(Icons.remove),
                            ),
                            Text('${extras[good] ?? 0}'),
                            IconButton(
                              tooltip: 'Add ${good.displayName}',
                              onPressed: (extras[good] ?? 0) < 99
                                  ? () => setState(
                                      () => extras[good] =
                                          (extras[good] ?? 0) + 1,
                                    )
                                  : null,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                  ],
                ],
              );
              final givePanel = bundleExtras(giveLeg, extraGive, give);
              final takePanel = bundleExtras(takeLeg, extraTake, take);
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    givePanel,
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.keyboard_double_arrow_down_rounded,
                          color: Color(0xffe5c183),
                        ),
                      ),
                    ),
                    takePanel,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: givePanel),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(9, 42, 9, 0),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: Color(0xffe5c183),
                    ),
                  ),
                  Expanded(child: takePanel),
                ],
              );
            },
          ),
          if (widget.onKindSelected == null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xff172b33),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xff3a5960)),
              ),
              child: Text(
                bank
                    ? 'Exchange $required ${give.displayName} for ${receipt * bankTimes} ${take.displayName}.'
                    : 'Offer ${tradeBundleText(gives)} for ${tradeBundleText(wants)} to ${target == -1 ? "everyone (first acceptance wins)" : s.players[target].id}.',
                style: const TextStyle(
                  color: Color(0xffdfeae9),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (!valid)
            Text(
              give == take
                  ? 'Choose different goods.'
                  : available < required
                  ? 'Insufficient goods to offer.'
                  : bank && bankAvailable < receipt * bankTimes
                  ? 'Bank stock is too low.'
                  : 'Check the trade terms.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: compactLandscape
            ? const EdgeInsets.fromLTRB(8, 2, 8, 4)
            : widget.onKindSelected == null
            ? const EdgeInsets.all(16)
            : const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: valid
                    ? () => Navigator.of(context).pop<MatchEvent>(
                        bank
                            ? BankExchange(give, take, times: bankTimes)
                            : ProposeTrade(
                                target,
                                give,
                                giveCount,
                                take,
                                takeCount,
                                counterOf: widget.counter?.id,
                                counterActor: widget.counter?.target == -1
                                    ? s.active
                                    : null,
                                giveBundle: gives,
                                wantBundle: wants,
                              ),
                      )
                    : null,
                child: Text(
                  bank
                      ? 'Exchange'
                      : widget.counter == null
                      ? 'Send offer'
                      : 'Send counter',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Only the public map and this responder’s choices remain visible.
class _TacticalPanel extends StatelessWidget {
  const _TacticalPanel({
    required this.state,
    required this.onEvent,
    required this.online,
  });
  final MatchState state;
  final ValueChanged<MatchEvent> onEvent;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final w = state.tactical!;
    final responder = w.responder;
    final label = switch (w.kind) {
      TacticalKind.bandit => 'Bandit interception',
      TacticalKind.governance => 'Governance challenge',
      TacticalKind.invasion => 'Invasion emergency aid',
    };
    final detail = switch (w.kind) {
      TacticalKind.bandit =>
        'An opponent is trying to steal a random good. '
            'Exhaust one active Knight to prevent the theft.',
      TacticalKind.governance =>
        'A targeted Governance card is pending. '
            'Spend the matching countercard to cancel it.',
      TacticalKind.invasion =>
        'One wheat gives +1 defence; one ore gives +2. '
            'Both go to the bank. The aid lasts for this invasion only.',
    };
    return ListView(
      key: ValueKey('response-${w.id}-$responder'),
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Response for ${state.players[responder].id}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xffe5c183),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(detail, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        if (w.kind == TacticalKind.invasion)
          InvasionMeter(
            state: state,
            compact: MediaQuery.sizeOf(context).width < 900,
          ),
        if (w.kind == TacticalKind.invasion &&
            MediaQuery.sizeOf(context).width >= 900)
          Text('Expected outcome: ${MatchEngine.invasionForecast(state)}'),
        if (w.kind == TacticalKind.bandit &&
            MatchEngine.canIntercept(state, responder))
          FilledButton.icon(
            onPressed: () => onEvent(
              RespondTactical(w.id, responder, TacticalChoice.intercept),
            ),
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Intercept with Knight'),
          ),
        if (w.kind == TacticalKind.governance)
          for (final i in MatchEngine.counterCards(state, responder, w.card!))
            FilledButton.icon(
              onPressed: () => onEvent(
                RespondTactical(
                  w.id,
                  responder,
                  TacticalChoice.counter,
                  cardIndex: i,
                ),
              ),
              icon: const Icon(Icons.gavel_outlined),
              label: Text(
                'Counter: ${state.players[responder].cards[i].definition.name}',
              ),
            ),
        if (w.kind == TacticalKind.invasion)
          for (final good in [Resource.wheat, Resource.ore])
            if ((state.players[responder].stores[good] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: FilledButton.icon(
                  onPressed: () => onEvent(
                    RespondTactical(
                      w.id,
                      responder,
                      TacticalChoice.aid,
                      good: good,
                    ),
                  ),
                  icon: const Icon(Icons.volunteer_activism_outlined),
                  label: Text('Pledge 1 ${good.displayName}'),
                ),
              ),
        OutlinedButton(
          onPressed: () =>
              onEvent(RespondTactical(w.id, responder, TacticalChoice.pass)),
          child: const Text('Pass'),
        ),
        const SizedBox(height: 12),
        Text(
          'Response allowance: ${state.reactionsUsed.contains(responder) ? 'spent' : 'available'}',
          style: const TextStyle(fontSize: 11),
        ),
        if (!online)
          TextButton(
            onPressed: () => onEvent(TimeoutTactical(w.id, responder)),
            child: const Text('Skip / timeout fallback'),
          ),
      ],
    );
  }
}

/// The shared tabletop projection used for painting, hit testing and target lists.
class BoardGeometry {
  BoardGeometry(this.size);
  final Size size;
  static const horizontalScale = 1.28;
  static const verticalScale = .72;
  // Reserve top/bottom gutters for coastal dock labels and leader lines.
  // The standard board spans 8 lattice units vertically.
  double get radius => math.min(
    size.width / (9.2 * horizontalScale),
    math.max(1, size.height - 64) / (8 * verticalScale),
  );
  Offset get center => Offset(size.width / 2, size.height / 2);
  Offset vertex(BoardVertex p) =>
      center +
      Offset(p.x * radius * horizontalScale, p.y * radius * verticalScale);
  Offset tile(HexCoord p) =>
      center +
      Offset(
        math.sqrt(3) * radius * (p.q + p.r / 2) * horizontalScale,
        1.5 * radius * p.r * verticalScale,
      );
}

class _Painter extends CustomPainter {
  _Painter(
    this.state,
    this.mode,
    this.selectedKnight, {
    required this.roadReveal,
    required this.roadCelebration,
    required this.highlightedRoads,
    required this.numberPulse,
    required this.banditBlock,
    this.humiliatedBanditTile,
    this.showTargets = true,
    this.hoverBuilds = false,
    this.hoveredRoad,
    this.cardRoadTargets = const {},
    this.cardVertexTargets = const {},
    this.cardTileTargets = const {},
    this.animatedRoad,
    this.animatedRoadStart,
  }) : super(
         repaint: Listenable.merge([
           roadReveal,
           roadCelebration,
           numberPulse,
           banditBlock,
           resourceIconStyle,
           resourceIconsRevision,
         ]),
       );
  final MatchState state;
  final bool showTargets;
  final bool hoverBuilds;
  final int? hoveredRoad;
  final Set<int> cardRoadTargets, cardVertexTargets, cardTileTargets;
  final _Move mode;
  final int? selectedKnight;
  final int? animatedRoad;
  final int? animatedRoadStart;
  final Animation<double> roadReveal;
  final Animation<double> roadCelebration;
  final List<int> highlightedRoads;
  final Animation<double> numberPulse;
  final Animation<double> banditBlock;
  final int? humiliatedBanditTile;

  @override
  void paint(Canvas canvas, Size size) {
    final g = BoardGeometry(size);
    for (var i = 0; i < state.board.tiles.length; i++) {
      final tile = state.board.tiles[i];
      final c = g.tile(tile.position), radius = g.radius;
      final hex = Path();
      for (var n = 0; n < 6; n++) {
        final angle = (n * 60 - 30) * math.pi / 180;
        final p =
            c +
            Offset(
              radius * math.cos(angle) * BoardGeometry.horizontalScale,
              radius * math.sin(angle) * BoardGeometry.verticalScale,
            );
        if (n == 0) {
          hex.moveTo(p.dx, p.dy);
        } else {
          hex.lineTo(p.dx, p.dy);
        }
      }
      hex.close();
      canvas.drawShadow(hex, const Color(0xff04151c), radius * .14, true);
      final base = landColors[tile.land.index];
      canvas.drawPath(
        hex,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, const Color(0xfff6e6aa), .13)!,
              Color.lerp(base, const Color(0xff142d32), .24)!,
            ],
          ).createShader(Rect.fromCircle(center: c, radius: radius)),
      );
      canvas.save();
      canvas.clipPath(hex);
      canvas.translate(c.dx, c.dy);
      // The board uses an oblique projection, but artwork must stay isotropic.
      _terrain(canvas, Offset.zero, radius, tile.land);
      canvas.restore();
      canvas.drawPath(
        hex,
        Paint()
          ..color = const Color(0xffb4b28b).withValues(alpha: .60)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      if (tile.productionNumber == state.dice &&
          state.dice != null &&
          i != state.banditTile) {
        canvas.drawPath(
          hex,
          Paint()
            ..color = const Color(0xfff4d88e)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.7,
        );
      }
      if (mode == _Move.bandit && i != state.banditTile) {
        canvas.drawPath(
          hex,
          Paint()
            ..color = const Color(0xffdce9b0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
      if (tile.productionNumber case final int number) {
        final activated =
            tile.productionNumber == state.dice && i != state.banditTile;
        final pulseProgress = numberPulse.value;
        final pulse = activated && pulseProgress < 1
            ? math.sin(pulseProgress * math.pi).abs()
            : 0.0;
        if (pulse > 0) {
          canvas.drawCircle(
            c,
            radius * (.38 + .19 * pulse),
            Paint()
              ..color = const Color(0xffffed92).withValues(alpha: .44 * pulse)
              ..style = PaintingStyle.stroke
              ..strokeWidth = radius * (.045 + .055 * pulse),
          );
        }
        canvas.drawShadow(
          Path()..addOval(
            Rect.fromCircle(center: c, radius: radius * (.35 + .045 * pulse)),
          ),
          Colors.black,
          radius * .06,
          true,
        );
        canvas.drawCircle(
          c,
          radius * (.35 + .045 * pulse),
          Paint()
            ..color = Color.lerp(
              const Color(0xfff5e6c4),
              const Color(0xffffefad),
              pulse,
            )!,
        );
        canvas.drawCircle(
          c,
          radius * (.30 + .045 * pulse),
          Paint()
            ..color = const Color(0xffb6a17c)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
        final ink = number == 6 || number == 8
            ? const Color(0xffa74637)
            : const Color(0xff23373c);
        _label(
          canvas,
          '$number',
          c - Offset(0, radius * .055),
          radius * (.46 + .08 * pulse),
          ink,
        );
        final pips = 6 - (7 - number).abs();
        for (var dot = 0; dot < pips; dot++) {
          canvas.drawCircle(
            c + Offset((dot - (pips - 1) / 2) * radius * .075, radius * .20),
            radius * .023,
            Paint()..color = ink,
          );
        }
      }
    }
    // Paint the Bandit above every hex, including its humiliation stamp.
    {
      final i = state.banditTile;
      final c = g.tile(state.board.tiles[i].position);
      final radius = g.radius;
      if (i == state.banditTile) {
        // Keep the production number unobscured; shame the robber whenever
        // the blocked number rolls or a knight stops a robbery.
        final bandit = c + Offset(radius * .51, -radius * .29);
        final progress = banditBlock.value;
        final humiliation = humiliatedBanditTile == i && progress < 1
            ? math.sin(progress * math.pi).abs()
            : 0.0;
        canvas.save();
        canvas.translate(
          bandit.dx +
              math.sin(progress * math.pi * 12) * radius * .12 * humiliation,
          bandit.dy + radius * .08 * humiliation,
        );
        canvas.rotate(math.sin(progress * math.pi * 7) * .24 * humiliation);
        canvas.scale(1 + .23 * humiliation, 1 - .32 * humiliation);
        canvas.drawCircle(
          Offset.zero,
          radius * .22,
          Paint()..color = const Color(0xff262d37),
        );
        _label(canvas, 'B', Offset.zero, radius * .22, Colors.white);
        canvas.restore();
        if (humiliation > .03) {
          canvas.drawCircle(
            bandit,
            radius * (.25 + humiliation * .18),
            Paint()
              ..color = const Color(0xffff6565).withValues(alpha: humiliation)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5,
          );
          final stamp = Rect.fromCenter(
            center:
                bandit +
                Offset(-radius * .20, -radius * (.34 + .08 * humiliation)),
            width: radius * 1.22,
            height: radius * .37,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(stamp, const Radius.circular(6)),
            Paint()
              ..color = const Color(0xff9a292c)
                  .withValues(alpha: .95 * humiliation),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(stamp, const Radius.circular(6)),
            Paint()
              ..color = const Color(0xffffefbf).withValues(alpha: humiliation)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
          _label(
            canvas,
            'NOPE!',
            stamp.center,
            radius * .27,
            Colors.white.withValues(alpha: humiliation),
          );
        }
      }
    }
    // Only preview the edge under the pointer; previews are not built roads.
    final legalRoads = showTargets && hoveredRoad != null
        ? <int>{hoveredRoad!}
        : <int>{};
    for (final e in state.topology.edges) {
      final owner = state.roads[e.id];
      if (owner == null && !legalRoads.contains(e.id)) continue;
      final reversed = e.id == animatedRoad && animatedRoadStart == e.b;
      final a = g.vertex(state.topology.vertices[reversed ? e.b : e.a]);
      final b = g.vertex(state.topology.vertices[reversed ? e.a : e.b]);
      if (owner == null) {
        // A dotted, translucent candidate can never be mistaken for a built road.
        final delta = b - a;
        final length = delta.distance;
        for (var d = 3.0; d < length - 2; d += 12) {
          canvas.drawCircle(
            a + delta * (d / length),
            2.8,
            Paint()..color = const Color(0xffb3ffe5).withValues(alpha: .72),
          );
        }
        final midpoint = (a + b) / 2;
        canvas.drawCircle(
          midpoint,
          9,
          Paint()..color = const Color(0xff142e35).withValues(alpha: .9),
        );
        canvas.drawCircle(
          midpoint,
          9,
          Paint()
            ..color = const Color(0xffb3ffe5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        _label(canvas, '+', midpoint, 10, const Color(0xffb3ffe5));
        continue;
      }
      final building = e.id == animatedRoad && roadReveal.value < 1;
      final tip = building ? Offset.lerp(a, b, roadReveal.value)! : b;
      // Restore the original simple two-stroke road: dark outline and a
      // single player-coloured centre. Keep the newer build reveal animation.
      canvas.drawLine(
        a,
        tip,
        Paint()
          ..color = const Color(0xff1b2834)
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a,
        tip,
        Paint()
          ..color = seatColors[owner]
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
      if (building) {
        canvas.drawCircle(
          tip,
          3.5 + 3 * (1 - roadReveal.value),
          Paint()..color = const Color(0xffffe6a5),
        );
      }
    }
    // Reveal the awarded continuous route in sequence, without game events.
    if (roadCelebration.value > 0 && roadCelebration.value < .80) {
      final route = highlightedRoads;
      for (var index = 0; index < route.length; index++) {
        final edge = state.topology.edges[route[index]];
        final a = g.vertex(state.topology.vertices[edge.a]);
        final b = g.vertex(state.topology.vertices[edge.b]);
        final progress = ((roadCelebration.value * 1.8 * route.length) - index)
            .clamp(0.0, 1.0);
        if (progress <= 0) continue;
        canvas.drawLine(
          a,
          Offset.lerp(a, b, progress)!,
          Paint()
            ..color = const Color(0xffffe8a7).withValues(alpha: .75)
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    final legal = <int>{
      if (hoverBuilds) ...MatchEngine.legalVertices(state),
      if (hoverBuilds) ...MatchEngine.legalUpgrades(state),
      if (hoverBuilds)
        for (final v in state.topology.vertices)
          if (MatchEngine.legalFort(state, v.id) ||
              MatchEngine.legalRecruit(state, v.id))
            v.id,
      ...switch (mode) {
        _Move.inspect => {
          ...MatchEngine.legalVertices(state),
          ...MatchEngine.legalUpgrades(state),
          for (var v = 0; v < state.topology.vertices.length; v++)
            if (MatchEngine.legalRecruit(state, v)) v,
        },
        _Move.village => MatchEngine.legalVertices(state).toSet(),
        _Move.upgrade => MatchEngine.legalUpgrades(state).toSet(),
        _Move.fortify => {
          for (final v in state.sites.keys)
            if (MatchEngine.legalFort(state, v)) v,
        },
        _Move.recruit => {
          for (var v = 0; v < state.topology.vertices.length; v++)
            if (MatchEngine.legalRecruit(state, v)) v,
        },
        _Move.activate => {
          for (final v in state.knights.keys)
            if (MatchEngine.legalActivate(state, v)) v,
        },
        _Move.promote => {
          for (final v in state.knights.keys)
            if (MatchEngine.legalPromote(state, v)) v,
        },
        _Move.knightMove =>
          selectedKnight == null
              ? {
                  for (final v in state.knights.keys)
                    if (state.knights[v]!.owner == state.active &&
                        state.knights[v]!.active &&
                        state.knights[v]!.actedTurn != state.turnSerial &&
                        MatchEngine.legalKnightDestinations(
                          state,
                          v,
                        ).isNotEmpty)
                      v,
                }
              : MatchEngine.legalKnightDestinations(
                  state,
                  selectedKnight!,
                ).toSet(),
        _ => <int>{},
      },
    };
    // Every junction is legal at the start of a match. Use restrained
    // markers so that dozens of bright dots do not overpower the hexes.
    final setupVillage = state.phase == MatchPhase.setupVillage;
    for (final v in state.topology.vertices) {
      final c = g.vertex(v);
      if (showTargets && legal.contains(v.id)) {
        canvas.drawCircle(
          c,
          math.max(setupVillage ? 5 : 7, g.radius * (setupVillage ? .15 : .22)),
          Paint()
            ..color = const Color(0xffaeffdf)
                .withValues(alpha: setupVillage ? .18 : .45),
        );
        canvas.drawCircle(
          c,
          math.max(
            setupVillage ? 2.6 : 3.5,
            g.radius * (setupVillage ? .075 : .10),
          ),
          Paint()
            ..color = const Color(0xfff6fff0)
                .withValues(alpha: setupVillage ? .88 : 1),
        );
      }
      final site = state.sites[v.id];
      if (site == null) continue;
      // Capitals remain taller than towns without obscuring nearby junctions.
      if (site.structure == Structure.capital) {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(.73);
        canvas.translate(-c.dx, -c.dy);
      }
      if (site.structure == Structure.capital) {
        final halo = Rect.fromCircle(
          center: c + const Offset(0, -7),
          radius: 30,
        );
        canvas.drawCircle(
          c + const Offset(0, -7),
          30,
          Paint()
            ..shader = RadialGradient(
              colors: [
                const Color(0xffffde89).withValues(alpha: .40),
                const Color(0xffffde89).withValues(alpha: .0),
              ],
            ).createShader(halo),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: c + const Offset(0, 10),
            width: 39,
            height: 12,
          ),
          Paint()..color = const Color(0xff221b25),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: c + const Offset(0, 10),
            width: 34,
            height: 7,
          ),
          Paint()..color = const Color(0xffffc86a).withValues(alpha: .75),
        );
      }
      final width = site.structure == Structure.village
          ? 15.0
          : site.structure == Structure.town
          ? 21.0
          : 32.0;
      final building = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c + const Offset(0, 2),
          width: width,
          height: site.structure == Structure.village ? width : width * .75,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(building, Paint()..color = const Color(0xff20313b));
      canvas.drawRRect(
        building.deflate(2),
        Paint()..color = seatColors[site.owner],
      );
      if (site.structure != Structure.village) {
        final ink = Paint()..color = const Color(0xff20313b);
        // Arched entrance and windows make towns readable at board scale.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: c + const Offset(0, 5),
              width: 5,
              height: 8,
            ),
            const Radius.circular(2),
          ),
          ink,
        );
        for (final dx in [-6.0, 6.0]) {
          canvas.drawRect(
            Rect.fromCenter(center: c + Offset(dx, 0), width: 3, height: 4),
            ink,
          );
        }
        if (site.structure == Structure.capital) {
          // A taller central keep, two battlement towers and a banner.
          final gold = Paint()..color = const Color(0xffffdd92);
          canvas.drawPath(
            Path()
              ..moveTo(c.dx - 13, c.dy - 9)
              ..lineTo(c.dx, c.dy - 23)
              ..lineTo(c.dx + 13, c.dy - 9)
              ..close(),
            Paint()..color = const Color(0xff24343b),
          );
          canvas.drawPath(
            Path()
              ..moveTo(c.dx - 10, c.dy - 10)
              ..lineTo(c.dx, c.dy - 20)
              ..lineTo(c.dx + 10, c.dy - 10)
              ..close(),
            gold,
          );
          canvas.drawLine(
            c + const Offset(0, -19),
            c + const Offset(0, -30),
            Paint()
              ..color = const Color(0xffffe5a5)
              ..strokeWidth = 1.8,
          );
          canvas.drawPath(
            Path()
              ..moveTo(c.dx + 1, c.dy - 30)
              ..lineTo(c.dx + 12, c.dy - 26)
              ..lineTo(c.dx + 1, c.dy - 22)
              ..close(),
            Paint()..color = seatColors[site.owner],
          );
          for (final dx in [-12.0, 12.0]) {
            canvas.drawRect(
              Rect.fromCenter(center: c + Offset(dx, -6), width: 6, height: 14),
              Paint()..color = seatColors[site.owner],
            );
            for (final tooth in [-2.0, 2.0]) {
              canvas.drawRect(
                Rect.fromCenter(
                  center: c + Offset(dx + tooth, -16),
                  width: 2,
                  height: 4,
                ),
                Paint()..color = seatColors[site.owner],
              );
            }
            canvas.drawRect(
              Rect.fromCenter(center: c + Offset(dx, -7), width: 2, height: 4),
              ink,
            );
            canvas.drawCircle(c + Offset(dx, -18), 2.5, gold);
          }
          canvas.drawCircle(
            c + const Offset(0, -5),
            2,
            Paint()..color = const Color(0xffffd77e),
          );
        }
      }
      if (site.structure == Structure.capital) canvas.restore();
      if (state.fortified.contains(v.id)) {
        _label(
          canvas,
          '▣',
          c + const Offset(12, -15),
          19,
          const Color(0xffffd77e),
        );
      }
      if (state.reaverScars.contains(v.id)) {
        _label(
          canvas,
          '!',
          c + const Offset(10, 11),
          14,
          const Color(0xffec6757),
        );
      }
    }
    for (final entry in state.knights.entries) {
      final knight = entry.value;
      final c = g.vertex(state.topology.vertices[entry.key]);
      canvas.drawCircle(c, 9, Paint()..color = const Color(0xff182a32));
      canvas.drawCircle(
        c,
        7,
        Paint()
          ..color = knight.active
              ? seatColors[knight.owner]
              : const Color(0xff879699),
      );
      _label(canvas, '${knight.rank.strength}', c, 11, const Color(0xff102028));
    }
    // Gold target rings remain visible above the pieces, without obscuring
    // their ownership colours. Only the candidate set is painted.
    const highlight = Color(0xffffe092);
    for (final edgeId in cardRoadTargets) {
      final edge = state.topology.edges[edgeId];
      final a = g.vertex(state.topology.vertices[edge.a]);
      final b = g.vertex(state.topology.vertices[edge.b]);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = highlight.withValues(alpha: .88)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle((a + b) / 2, 5, Paint()..color = Colors.white);
    }
    for (final vertex in cardVertexTargets) {
      final spot = g.vertex(state.topology.vertices[vertex]);
      canvas.drawCircle(
        spot,
        math.max(13, g.radius * .35),
        Paint()
          ..color = highlight.withValues(alpha: .95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    for (final tile in cardTileTargets) {
      final spot = g.tile(state.board.tiles[tile].position);
      canvas.drawCircle(
        spot,
        g.radius * .61,
        Paint()
          ..color = highlight.withValues(alpha: .92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }
    // The top/bottom docks need to sit *outside* the playable hexes rather
    // than on top of them, especially when the board is vertically compact.
    final vertices = state.topology.vertices.map(g.vertex).toList();
    final boardBounds = Rect.fromLTRB(
      vertices.map((p) => p.dx).reduce(math.min),
      vertices.map((p) => p.dy).reduce(math.min),
      vertices.map((p) => p.dx).reduce(math.max),
      vertices.map((p) => p.dy).reduce(math.max),
    );
    for (final dock in state.topology.docks) {
      final a = g.vertex(state.topology.vertices[dock.edge.a]);
      final b = g.vertex(state.topology.vertices[dock.edge.b]);
      final middle = (a + b) / 2;
      final text = TextPainter(
        text: TextSpan(
          text: dock.label,
          style: const TextStyle(
            fontFamily: 'NotoSans',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xffffe5b2),
            backgroundColor: Color(0xff182a31),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final label = dockLabelPosition(
        size: size,
        edgeMidpoint: middle,
        boardBounds: boardBounds,
        labelSize: text.size,
        radius: g.radius,
      );
      // Highlight the exact dock edge and end the leader at the label frame.
      final shore = Paint()
        ..color = const Color(0xffffd68a)
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(a, b, shore);
      canvas.drawCircle(middle, 4.4, Paint()..color = const Color(0xff182a31));
      canvas.drawCircle(middle, 2.8, Paint()..color = const Color(0xffffefba));
      final badge = Rect.fromCenter(
        center: label,
        width: text.width + 12,
        height: text.height + 8,
      );
      final delta = label - middle;
      final xFraction = delta.dx.abs() < .001
          ? double.infinity
          : (badge.width / 2) / delta.dx.abs();
      final yFraction = delta.dy.abs() < .001
          ? double.infinity
          : (badge.height / 2) / delta.dy.abs();
      final boundary = label - delta * math.min(xFraction, yFraction);
      canvas.drawLine(
        middle,
        boundary,
        Paint()
          ..color = const Color(0xff101c24)
          ..strokeWidth = 4.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        middle,
        boundary,
        Paint()
          ..color = const Color(0xffffe1a0)
          ..strokeWidth = 2.3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badge, const Radius.circular(5)),
        Paint()..color = const Color(0xff182a31),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badge, const Radius.circular(5)),
        Paint()
          ..color = const Color(0xffc7ac78)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .9,
      );
      text.paint(canvas, label - Offset(text.width / 2, text.height / 2));
    }
  }

  // Geometric marks are fixed decorations for each terrain.
  // They never read or advance the match's random event stream.
  void _terrain(Canvas canvas, Offset c, double r, Land land) {
    final resource = switch (land) {
      Land.woodland => Resource.wood,
      Land.clayBeds => Resource.brick,
      Land.fields => Resource.wheat,
      Land.meadows => Resource.wool,
      Land.ridges => Resource.ore,
      Land.barren => null,
    };
    if (resource == null) {
      // Only the barren terrain decoration follows the board projection.
      canvas.save();
      canvas.scale(BoardGeometry.horizontalScale, BoardGeometry.verticalScale);
      final dune = Paint()
        ..color = const Color(0xffe9cf91).withValues(alpha: .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .035;
      for (final y in [-.5, .5]) {
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r * .55, c.dy + r * y)
            ..quadraticBezierTo(
              c.dx,
              c.dy + r * (y - .25),
              c.dx + r * .55,
              c.dy + r * y,
            ),
          dune,
        );
      }
      canvas.restore();
      return;
    }
    for (final side in [-1.0, 1.0]) {
      paintResourceIcon(
        canvas,
        c + Offset(side * r * .60 * BoardGeometry.horizontalScale, 0),
        r * .42,
        resource,
      );
    }
  }

  void _label(Canvas canvas, String value, Offset c, double size, Color color) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: 'NotoSans',
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, c - Offset(p.width / 2, p.height / 2));
  }

  bool _sameTargets(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  bool shouldRepaint(_Painter old) =>
      !identical(old.state, state) ||
      old.mode != mode ||
      old.showTargets != showTargets ||
      old.hoverBuilds != hoverBuilds ||
      old.hoveredRoad != hoveredRoad ||
      !_sameTargets(old.cardRoadTargets, cardRoadTargets) ||
      !_sameTargets(old.cardVertexTargets, cardVertexTargets) ||
      !_sameTargets(old.cardTileTargets, cardTileTargets) ||
      old.selectedKnight != selectedKnight ||
      old.animatedRoad != animatedRoad ||
      old.roadReveal != roadReveal ||
      old.banditBlock != banditBlock ||
      old.humiliatedBanditTile != humiliatedBanditTile;
}
