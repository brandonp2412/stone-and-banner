import 'resource_transfer.dart';

// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;

import 'compact_layout.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/semantics.dart' show SemanticsProperties;

import 'game_colors.dart';

import 'package:flutter/services.dart';

import 'dock_label_layout.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/advanced.dart';
import '../engine/cards.dart';
import '../engine/board.dart';
import '../engine/game.dart';
import '../engine/match.dart';
import '../network/room_protocol.dart';
import 'strategy_hand.dart';
import 'labels.dart';
import 'resource_harvest.dart';
import 'resource_icon.dart';
import 'resource_label.dart';
import 'trade_market.dart';
import 'trade_picker.dart';
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
  guardMove,
}

const seatColors = [
  Color(0xff40d5b4),
  Color(0xffffc477),
  Color(0xffd5a6f7),
  Color(0xff8ebdff),
  Color(0xffff8299),
  Color(0xffe4df75),
];
const landColors = [
  Color(0xff437c60),
  Color(0xffb46c4d),
  Color(0xffb9a05e),
  Color(0xff90ab61),
  Color(0xff8395a2),
  Color(0xff81705c),
];

final _capitalImage = ValueNotifier<ui.Image?>(null);
Future<void>? _capitalImageLoad;

Future<void> _loadCapitalImage() async {
  final data = await rootBundle.load('assets/art/capital.png');
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  try {
    _capitalImage.value = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

final _capitalPaints = [
  Paint()..filterQuality = FilterQuality.medium,
  for (final color in seatColors.skip(1))
    Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = _capitalColorFilter(color),
];

ColorFilter _capitalColorFilter(Color color) {
  // Scale the color shift by the source teal's green–red difference so
  // the artwork retains its dark outline and pale highlights.
  const tealChroma = 205 - 56;
  final red = (color.r * 255 - 56) / tealChroma;
  final green = (color.g * 255 - 205) / tealChroma;
  final blue = (color.b * 255 - 182) / tealChroma;
  return ColorFilter.matrix([
    1 - red,
    red,
    0,
    0,
    0,
    -green,
    1 + green,
    0,
    0,
    0,
    -blue,
    blue,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);
}

class MatchView extends StatefulWidget {
  const MatchView({
    super.key,
    required this.state,
    required this.onEvent,
    this.observing = false,
    this.tradeReplyAllowed = false,
    this.online = false,
    this.onlineView,
    this.onlineTurnSeconds,
    this.viewingSeat,
    this.computerSeats = const <int>{},
    this.visibleSeat,
    this.waitingMessage,
    this.onFastForward,
    this.fastForwardingBots = false,
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
  final int? onlineTurnSeconds;
  final Map<String, dynamic>? onlineView;
  final int? viewingSeat;
  final Set<int> computerSeats;
  final int? visibleSeat;
  final String? waitingMessage;
  final VoidCallback? onFastForward;
  final bool fastForwardingBots;
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

  int? selectedGuard;
  final _boardHoverPosition = ValueNotifier<Offset?>(null);
  RollDice? _rollingDice;
  bool _skipBotDice = false;
  int _diceAnimationSerial = 0;
  late final AnimationController _roadController;
  late final Animation<double> _roadReveal;
  int? _animatedRoad;
  int? _animatedRoadStart;
  Timer? _turnClock;
  int _secondsLeft = 90; // Set from online/offline rules at initialization.
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
      _seenHints
        ..clear()
        ..addAll(prefs.getStringList('gameplay_hints_seen_v1') ?? []);
      _dismissedHintContext = null;
      _hintsLoaded = true;
    });
  }

  final _realmHintTarget = GlobalKey();
  final _actionsHintTarget = GlobalKey();
  final _boardHintTarget = GlobalKey();
  final _turnHintTarget = GlobalKey();
  final _panelHintTarget = GlobalKey();
  final _tabHintTargets = List.generate(3, (_) => GlobalKey());

  String get _hintContext =>
      '${s.seed}:${s.phase}:${s.tactical?.id}:$_tab:$move:$_mobilePage';

  GameplayHint? get _activeGameplayHint {
    if (!_hintsLoaded ||
        !_hintsEnabled ||
        // Multiplayer instruction overlays can consume a timed turn. Players
        // can still consult the rulebook without blocking each other's game.
        widget.online ||
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
        : hint.id == 'roll' || hint.id == 'invasion'
        ? (onMap ? _turnHintTarget : _panelHintTarget)
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
  late final AnimationController _crownRoadController;
  late final AnimationController _roadBreakController;
  int? _brokenRoadOwner, _roadBreakVertex;
  List<int> _brokenRoadRoute = const [];
  int _roadBeforeBreak = 0, _roadAfterBreak = 0;
  bool _roadAwardLost = false;
  int? _crownRoadWinner;
  List<int> _crownRoadRoute = const [];
  bool _unseenCard = false;
  String? _newCardNotice;
  Timer? _newCardTimer;
  String? _fallenCityOwner;
  int _fallenCityVp = 0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleMainActionKey);
    _secondsLeft = widget.onlineTurnSeconds ?? (widget.online ? 150 : 90);
    unawaited(loadResourceIcons());
    unawaited(_capitalImageLoad ??= _loadCapitalImage());
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
    _roadBreakController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3400),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _brokenRoadOwner = null);
          }
        });
    _crownRoadController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3200),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _crownRoadWinner = null);
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
  _Move get move => s.pendingDiscards.isNotEmpty
      ? _Move.inspect
      : switch (s.phase) {
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
                        ResourceTransfer(
                          title: 'DISCARD',
                          selected: selected,
                          holdings: hand,
                          limit: required,
                          onChanged: (next) => update(() {
                            selected
                              ..clear()
                              ..addAll(next);
                          }),
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
    if (s.pendingDiscards.isNotEmpty && event is! DiscardResources) return;
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
      selectedGuard = null;
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
      selectedGuard = null;
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
                  leading: ResourceIcon(entry.key, size: 24),
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
        s.active == viewerSeat &&
        _mapCardOptions.any(
          (option) => mapEquals(option.toJson(), selected!.toJson()),
        )) {
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
        content: ResourceLabel('Cost: $cost', showNames: true),
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
        content: ResourceLabel(
          'Cost: ${_costLabel(MatchEngine.effectiveRoadCost(s))}',
          showNames: true,
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
    if (widget.observing ||
        s.tactical != null ||
        s.pendingDiscards.isNotEmpty) {
      return null;
    }
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
        30,
        g.radius * (move == _Move.village || move == _Move.upgrade ? .5 : .45),
      );
      for (final id in availableTargets) {
        if ((point - g.vertex(s.topology.vertices[id])).distance <= radius) {
          return '$_instruction · click to select';
        }
      }
      return null;
    }
    if (s.phase != MatchPhase.actions) return null;
    for (final id in s.guards.keys) {
      if ((point - g.vertex(s.topology.vertices[id])).distance <=
          math.max(22, g.radius * .35)) {
        final actions = [
          if (MatchEngine.legalActivate(s, id)) 'activate',
          if (MatchEngine.legalPromote(s, id)) 'upgrade',
        ];
        return actions.isEmpty
            ? 'Inspect Guard · click for details'
            : 'Inspect Guard · ${actions.join(' or ')} available';
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
            ? 'Upgrade village · ${_upgradeCostLabel()}'
            : MatchEngine.legalVillage(s, id)
            ? 'Build a village · ${_costLabel(MatchEngine.villageCost)}'
            : 'Build Guard · ${_costLabel(MatchEngine.recruitCost)}';
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
    if (s.pendingDiscards.isNotEmpty) return;
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
      if (best != null && distance <= math.max(30, g.radius * .5)) {
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
      _Move.guardMove,
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
          for (final v in s.guards.keys)
            if (MatchEngine.legalActivate(s, v)) v,
        ],
        _Move.promote => [
          for (final v in s.guards.keys)
            if (MatchEngine.legalPromote(s, v)) v,
        ],
        _Move.guardMove =>
          selectedGuard == null
              ? [
                  for (final v in s.guards.keys)
                    if (s.guards[v]!.owner == s.active &&
                        s.guards[v]!.active &&
                        s.guards[v]!.actedTurn != s.turnSerial &&
                        MatchEngine.legalGuardDestinations(s, v).isNotEmpty)
                      v,
                ]
              : MatchEngine.legalGuardDestinations(s, selectedGuard!),
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
          send(RecruitGuard(best));
          break;
        case _Move.activate:
          send(ActivateGuard(best));
          break;
        case _Move.promote:
          send(PromoteGuard(best));
          break;
        case _Move.guardMove:
          if (selectedGuard == null) {
            setState(() => selectedGuard = best);
          } else {
            send(MoveGuard(selectedGuard!, best));
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
          barrierDismissible: true,
          builder: (context) => CompactAlertDialog(
            title: const Text('Bandit · choose who to rob'),
            content: const Text(
              'Choose a neighbour. The good is drawn from their hand using the saved seed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              for (final n in victims)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: seatColors[n],
                    foregroundColor: const Color(0xff172025),
                  ),
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
        for (final entry in s.guards.entries) {
          if ((tap - g.vertex(s.topology.vertices[entry.key])).distance >
              math.max(22, g.radius * .35)) {
            continue;
          }
          final vertex = entry.key;
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => CompactAlertDialog(
              title: Text(
                '${entry.value.rank.name} Guard · strength ${entry.value.rank.strength}',
              ),
              content: ResourceLabel(
                '${entry.value.active ? 'Active' : 'Inactive'} · Upgrade cost: ${entry.value.rank == GuardRank.champion ? 'Maximum rank' : _costLabel(MatchEngine.promotionCost(entry.value.rank))}.',
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
                          send(PromoteGuard(vertex));
                        }
                      : null,
                  child: const Text('Upgrade Guard'),
                ),
                if (MatchEngine.legalActivate(s, vertex))
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      send(ActivateGuard(vertex));
                    },
                    child: ResourceLabel(
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
                upgrade ? 'Upgrade village?' : 'Build at this junction',
              ),
              content: ResourceLabel(
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
                    child: const Text('Upgrade village'),
                  ),
                if (canVillage)
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, PlaceVillage(vertex)),
                    child: ResourceLabel(
                      'Build village · ${_costLabel(MatchEngine.villageCost)}',
                    ),
                  ),
                if (canRecruit)
                  OutlinedButton(
                    key: const ValueKey('build-guard-at-junction'),
                    onPressed: () =>
                        Navigator.pop(context, RecruitGuard(vertex)),
                    child: ResourceLabel(
                      'Build Guard · ${_costLabel(s.players[viewerSeat].level(StrategyDeck.governance) >= 4 ? {Resource.wool: 1} : MatchEngine.recruitCost)}',
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
      for (final v in s.guards.keys)
        if (MatchEngine.legalActivate(s, v)) v,
    ],
    _Move.promote => [
      for (final v in s.guards.keys)
        if (MatchEngine.legalPromote(s, v)) v,
    ],
    _Move.guardMove =>
      selectedGuard == null
          ? [
              for (final v in s.guards.keys)
                if (s.guards[v]!.owner == s.active &&
                    s.guards[v]!.active &&
                    s.guards[v]!.actedTurn != s.turnSerial &&
                    MatchEngine.legalGuardDestinations(s, v).isNotEmpty)
                  v,
            ]
          : MatchEngine.legalGuardDestinations(s, selectedGuard!),
    _Move.bandit => [
      for (var i = 0; i < s.board.tiles.length; i++)
        if (i != s.banditTile) i,
    ],
    _Move.inspect => <int>[],
  };

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
              width: mobileTrade ? double.infinity : 740,
              height: mobileTrade
                  ? MediaQuery.sizeOf(context).height
                  : math.min(
                      MediaQuery.sizeOf(context).height - (fromTray ? 90 : 32),
                      500.0,
                    ),
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

  bool _canReplyToIncoming(TradeProposal offer) =>
      s.phase == MatchPhase.actions &&
      s.pendingDiscards.isEmpty &&
      s.tactical == null &&
      offer.canRespond(viewerSeat) &&
      ((!widget.observing && s.active == viewerSeat) ||
          (offer.proposer == s.active &&
              (!widget.online || widget.tradeReplyAllowed)));

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
                _canReplyToIncoming(offer),
          )
          .firstOrNull;
      if (incoming == null) return;
      _notifiedTradeOfferIds.add(incoming.id);
      setState(() {
        _incomingTradeOpen = true;
        _incomingDialogOfferId = incoming.id;
      });
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
        if (!mounted) return;
        setState(() {
          _incomingTradeOpen = false;
          _incomingDialogContext = null;
          _incomingDialogOfferId = null;
        });
        _scheduleIncomingTrade();
      });
    });
  }

  final _panelScroll = List.generate(4, (_) => ScrollController());

  bool get _compact => MediaQuery.sizeOf(context).height < 350;

  int _tab = 0;
  // null: map; -1: full-screen actions.
  int? _mobilePage;

  void _openMobileCategory(int tab) {
    // Viewing any category is allowed, even while another player acts.
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
    FocusManager.instance.removeEarlyKeyEventHandler(_handleMainActionKey);
    _boardHoverPosition.dispose();
    _turnClock?.cancel();
    _newCardTimer?.cancel();
    _roadController.dispose();
    _numberPulseController.dispose();
    _banditBlockController.dispose();
    _cardsTabController.dispose();
    _cityFallController.dispose();
    _crownRoadController.dispose();
    _roadBreakController.dispose();
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
              offer.id == _incomingDialogOfferId && _canReplyToIncoming(offer),
        )) {
      final offerId = _incomingDialogOfferId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _incomingDialogOfferId != offerId) return;
        final dialogContext = _incomingDialogContext;
        if (dialogContext == null || !dialogContext.mounted) return;
        final route = ModalRoute.of(dialogContext);
        // Remove this exact stale dialog, even if a mandatory discard or
        // tactical response opened over it. Do not pop unrelated routes.
        if (route != null && route.isActive) {
          Navigator.of(dialogContext).removeRoute(route);
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
      _crownRoadWinner = null;
      _crownRoadRoute = const [];
      _crownRoadController.reset();
      _roadBreakController.reset();
      _brokenRoadOwner = null;
      _brokenRoadRoute = const [];
      _roadBreakVertex = null;
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
    final skipping =
        _skipBotDice ||
        widget.fastForwardingBots ||
        oldWidget.fastForwardingBots;
    final newEvents = s.seed == oldWidget.state.seed
        ? s.events.skip(oldWidget.state.events.length).toList()
        : <MatchEvent>[];
    final rollIndex = newEvents.lastIndexWhere((event) => event is RollDice);
    final roll = rollIndex < 0 ? null : newEvents[rollIndex] as RollDice;
    final rolled =
        roll != null &&
        (!skipping ||
            (!widget.computerSeats.contains(s.active) &&
                !newEvents
                    .skip(rollIndex + 1)
                    .any((event) => event is EndTurn)));
    if (rolled) {
      _rollingDice = roll;
      _diceAnimationSerial++;
    } else if (s.seed != oldWidget.state.seed ||
        (skipping && roll != null) ||
        (widget.fastForwardingBots && !oldWidget.fastForwardingBots)) {
      _rollingDice = null;
    }
    if (widget.onFastForward == null) _skipBotDice = false;
    if (rolled && !MediaQuery.disableAnimationsOf(context)) {
      _numberPulseController.forward(from: 0);
    }
    final blockedTheft = s.events
        .skip(oldWidget.state.events.length)
        .any(
          (event) =>
              event is RespondTactical &&
              event.choice == TacticalChoice.intercept,
        );
    if ((rolled &&
            s.dice != null &&
            s.board.tiles[s.banditTile].productionNumber == s.dice) ||
        blockedTheft) {
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
    if (!skipping && additions.isNotEmpty) {
      _animatedRoad = additions.last;
      final old = oldWidget.state;
      final edge = old.topology.edges[_animatedRoad!];
      final owner = s.roads[_animatedRoad!];
      bool connected(int vertex) =>
          old.sites[vertex]?.owner == owner ||
          old.topology.vertices[vertex].edges.any(
            (id) => old.roads[id] == owner,
          );
      // Reveal outwards from the village or existing road network, rather
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
    final previous = oldWidget.state;
    if (!skipping &&
        s.seed == previous.seed &&
        s.events.length > previous.events.length) {
      final holder = previous.crownRoadHolder;
      if (holder != null) {
        final before = MatchEngine.crownRoad(previous, holder);
        final after = MatchEngine.crownRoad(s, holder);
        final route = MatchEngine.crownRoadPath(previous, holder);
        final vertices = {
          for (final id in route) ...[
            s.topology.edges[id].a,
            s.topology.edges[id].b,
          ],
        };
        final blockers = vertices.where(
          (v) =>
              s.guards[v] != null &&
              s.guards[v]!.owner != holder &&
              previous.guards[v]?.owner != s.guards[v]!.owner,
        );
        if (after < before &&
            blockers.isNotEmpty &&
            !MediaQuery.disableAnimationsOf(context)) {
          _brokenRoadOwner = holder;
          _brokenRoadRoute = route;
          _roadBreakVertex = blockers.first;
          _roadBeforeBreak = before;
          _roadAfterBreak = after;
          _roadAwardLost = s.crownRoadHolder != holder;
          _roadBreakController.forward(from: 0);
        }
      }
    }
    if (!skipping &&
        s.seed == oldWidget.state.seed &&
        s.crownRoadHolder != null &&
        s.crownRoadHolder != oldWidget.state.crownRoadHolder) {
      _crownRoadWinner = s.crownRoadHolder;
      _crownRoadRoute = MatchEngine.crownRoadPath(s, s.crownRoadHolder!);
      if (!MediaQuery.disableAnimationsOf(context)) {
        _crownRoadController.forward(from: 0);
      } else {
        _crownRoadWinner = null;
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
      _secondsLeft = widget.onlineTurnSeconds ?? (widget.online ? 150 : 90);
      _expiredEventCount = null;
    }
    if (widget.onlineTurnSeconds != null) {
      _secondsLeft = widget.onlineTurnSeconds!;
    }
    if (_choosingCardTarget) {
      final index = _mapCardOptions.first.handIndex;
      final before = oldWidget.state.players[oldSeat].cards;
      final now = s.players[viewerSeat].cards;
      final stillHeld =
          oldSeat == viewerSeat &&
          oldWidget.state.seed == s.seed &&
          s.active == viewerSeat &&
          s.phase == MatchPhase.actions &&
          s.pendingDiscards.isEmpty &&
          s.tactical == null &&
          !widget.observing &&
          index >= 0 &&
          index < before.length &&
          index < now.length &&
          before[index].track == now[index].track &&
          before[index].index == now[index].index;
      if (stillHeld) {
        final onlineOptions = widget.onlineView?['options'] as Map?;
        _mapCardOptions = widget.online && onlineOptions != null
            ? [
                for (final raw in (onlineOptions['$index'] as List? ?? []))
                  RoomProtocol.eventFromJson(
                    Map<String, dynamic>.from(raw as Map),
                  ) as PlayStrategyCard,
              ]
            : MatchEngine.legalCardPlays(s, index);
      }
      if (!stillHeld || _mapCardOptions.isEmpty) {
        _mapCard = null;
        _mapCardOptions = const [];
      }
    }
    if (oldWidget.state.active != s.active ||
        oldWidget.state.phase != s.phase) {
      choice = _Move.inspect;
      selectedGuard = null;
    }
  }

  String get _instruction =>
      widget.online && widget.observing && s.phase != MatchPhase.finished
      ? 'Waiting for players'
      : s.pendingDiscards.isNotEmpty
      ? 'Discard resources'
      : s.tactical != null
      ? 'A response is pending'
      : switch (s.phase) {
          MatchPhase.setupVillage =>
            s.setupStep < s.players.length
                ? 'Place your village'
                : 'Place your town',
          MatchPhase.setupRoad =>
            s.setupStep < s.players.length
                ? 'Connect your village'
                : 'Connect your town',
          MatchPhase.roll => '',
          MatchPhase.bandit => 'Move the Bandit',
          MatchPhase.invasion => 'Defend the realm',
          MatchPhase.finished =>
            '${s.players[MatchEngine.winner(s) ?? s.active].id} wins!',
          MatchPhase.actions => switch (move) {
            _Move.inspect => 'Shape your realm',
            _Move.village => 'Place a village',
            _Move.road => 'Build a road',
            _Move.upgrade => 'Upgrade a village',
            _Move.fortify => 'Fortify a town',
            _Move.recruit => 'Recruit a Guard',
            _Move.activate => 'Activate a Guard',
            _Move.promote => 'Promote a Guard',
            _Move.guardMove =>
              selectedGuard == null ? 'Select a Guard' : 'Choose a destination',
            _Move.bandit => 'Move the Bandit',
          },
        };

  String get _hint => widget.fastForwardingBots && !isCompactLandscape(context)
      ? 'Fast-forwarding bots…'
      : widget.online && widget.observing && s.phase != MatchPhase.finished
      ? widget.waitingMessage ?? ''
      : s.pendingDiscards.isNotEmpty
      ? 'Finish discarding before moving the Bandit'
      : s.tactical != null
      ? 'Resolve this response to continue the turn'
      : switch (s.phase) {
          MatchPhase.setupVillage =>
            'Tap a glowing junction · first placements are free',
          MatchPhase.setupRoad =>
            s.setupStep < s.players.length
                ? 'Tap an edge beside your new village'
                : 'Tap an edge beside your new town',
          MatchPhase.roll => '',
          MatchPhase.bandit => 'Tap another hex, then choose a neighbour',
          MatchPhase.invasion => 'Review the fleet and your shared defence',
          MatchPhase.finished => '15 Renown · a realm to remember',
          MatchPhase.actions => switch (move) {
            _Move.road =>
              '${_costLabel(MatchEngine.effectiveRoadCost(s))} · tap a connected edge',
            _Move.village =>
              '${_costLabel(MatchEngine.villageCost)} · tap a glowing junction',
            _Move.inspect => 'Build, trade or play a card',
            _ => 'Tap a glowing target on the map',
          },
        };

  // Reserve room for the raid/dice badges and port labels as well as the toast.
  bool get _hasTopActivitySpace {
    final viewport = MediaQuery.sizeOf(context);
    if (viewport.width < 600 || _mobilePage != null) return false;
    final padding = MediaQuery.paddingOf(context);
    final height =
        viewport.height -
        padding.vertical -
        160 -
        (viewport.width < 900 ? 0 : _instructionHeight);
    final rail = viewport.width < 900
        ? 0.0
        : viewport.width >= 1200 && height >= 550
        ? (viewport.width * .25).clamp(320.0, 420.0)
        : math.min(320.0, viewport.width * .48);
    final geometry = BoardGeometry(Size(viewport.width - rail, height));
    final terrainTop =
        geometry.center.dy - 4 * geometry.radius * geometry.verticalFactor;
    return viewport.width - rail >= 560 &&
        terrainTop >= 170 &&
        MediaQuery.textScalerOf(context).scale(14) <= 20;
  }

  @override
  void reassemble() {
    super.reassemble();
    FocusManager.instance.removeEarlyKeyEventHandler(_handleMainActionKey);
    FocusManager.instance.addEarlyKeyEventHandler(_handleMainActionKey);
  }

  KeyEventResult _handleMainActionKey(KeyEvent event) {
    if (!mounted ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.space ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        ModalRoute.of(context)?.isCurrent != true ||
        FocusManager.instance.primaryFocus?.context?.widget is EditableText ||
        _activeGameplayHint != null) {
      return KeyEventResult.ignored;
    }
    final action = _turnActionCallback;
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleDiscardDialog();
    final phase = s.phase;
    final gameplayHint = _activeGameplayHint;
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final portrait =
        MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width &&
        MediaQuery.sizeOf(context).width < 600;
    return PopScope(
      canPop: !mobile || _mobilePage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mobile && _mobilePage != null) _backMobile();
      },
      child: Material(
        color: gameColor(context, const Color(0xff101e25)),
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  if (!mobile || _mobilePage == null) _playerBar(),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            key: _panelHintTarget,
                            builder: (context, bounds) {
                              if (mobile) return _mobileLayout(phase);
                              final desktop =
                                  bounds.maxWidth >= 1200 &&
                                  bounds.maxHeight >= 550;
                              final railWidth = desktop
                                  ? (bounds.maxWidth * .25).clamp(320.0, 420.0)
                                  : math.min(320.0, bounds.maxWidth * .48);
                              return Column(
                                children: [
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: _map()),
                                        SizedBox(
                                          width: railWidth,
                                          child: Material(
                                            color: gameColor(
                                              context,
                                              const Color(0xff182a31),
                                            ),
                                            child: Column(
                                              children: [
                                                if (s.tactical == null ||
                                                    widget.observing)
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
                                                          controller:
                                                              _panelScroll[_tab],
                                                          thumbVisibility: true,
                                                          interactive: true,
                                                          child: ListView(
                                                            controller:
                                                                _panelScroll[_tab],
                                                            key: PageStorageKey(
                                                              'panel-$_tab',
                                                            ),
                                                            padding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      _compact
                                                                      ? 8
                                                                      : 12,
                                                                  vertical:
                                                                      _compact
                                                                      ? 4
                                                                      : 12,
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
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _desktopFooter(railWidth),
                                ],
                              );
                            },
                          ),
                        ),
                        // Keep the roll above the changing turn layout so a
                        // bot-to-human handoff cannot remount its animation.
                        if (_rollingDice case final dice?)
                          Positioned.fill(
                            key: ValueKey('dice-overlay-$_diceAnimationSerial'),
                            child: IgnorePointer(
                              child: LayoutBuilder(
                                builder: (context, bounds) {
                                  final width = bounds.maxWidth;
                                  final rail = mobile
                                      ? 0.0
                                      : width >= 1200 && bounds.maxHeight >= 550
                                      ? (width * .25).clamp(320.0, 420.0)
                                      : math.min(320.0, width * .48);
                                  return Padding(
                                    padding: EdgeInsets.only(right: rail),
                                    child: DiceRoll(
                                      first: dice.first,
                                      second: dice.second,
                                      onComplete: () {
                                        if (mounted &&
                                            identical(_rollingDice, dice)) {
                                          setState(() => _rollingDice = null);
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        if ((portrait || !mobile || _hasTopActivitySpace) &&
                            _mobilePage == null)
                          Positioned(
                            top: 4,
                            left: portrait ? 12 : 132,
                            right: portrait
                                ? 12
                                : 132 +
                                      (mobile
                                          ? 0
                                          : MediaQuery.sizeOf(context).width >=
                                                    1200 &&
                                                MediaQuery.sizeOf(context)
                                                            .height -
                                                        MediaQuery.paddingOf(
                                                          context,
                                                        ).vertical -
                                                        160 -
                                                        _instructionHeight >=
                                                    550
                                          ? (MediaQuery.sizeOf(context).width *
                                                    .25)
                                                .clamp(320.0, 420.0)
                                          : math.min(
                                              320.0,
                                              MediaQuery.sizeOf(context).width *
                                                  .48,
                                            )),
                            child: Center(
                              child: MatchActivity(
                                key: ValueKey(
                                  portrait
                                      ? 'portrait-reaction-toast'
                                      : 'top-reaction-toast',
                                ),
                                showActivity: portrait || _hasTopActivitySpace,
                                fastForwardingBots: widget.fastForwardingBots,
                                state: s,
                                viewerSeat: viewerSeat,
                                computerSeats: widget.computerSeats,
                                emote: widget.networkEmote ?? _emote,
                                emoteSerial:
                                    widget.online && widget.onEmote != null
                                    ? widget.networkEmoteSerial
                                    : _emoteSerial,
                                emoteSeat: widget.networkEmoteSeat,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!mobile || _mobilePage == null || _tradeComposerOpen)
                    _resourceTray(anchorHarvest: true),
                ],
              ),
            ),
            if (!widget.fastForwardingBots)
              Positioned.fill(
                child: ResourceHarvest(
                  state: s,
                  seat: viewerSeat,
                  anchors: _resourceAnchors,
                  deferAnimation: _rollingDice != null,
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
            if ((!mobile || _mobilePage == null) &&
                !(MediaQuery.sizeOf(context).height >
                        MediaQuery.sizeOf(context).width &&
                    MediaQuery.sizeOf(context).width < 600))
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
                    color: gameColor(context, const Color(0xff584322)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: gameColor(context, const Color(0xffffe092)),
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
                          Icon(
                            Icons.place_rounded,
                            color: gameColor(context, const Color(0xffffe092)),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              _mapCardTargetMessage,
                              maxLines: 2,
                              style: TextStyle(fontWeight: FontWeight.w800),
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
                    color: gameColor(context, const Color(0xff60451d)),
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
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: gameColor(
                                context,
                                const Color(0xffffe092),
                              ),
                              size: 29,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'NEW STRATEGY CARD!',
                                    style: TextStyle(
                                      color: gameColor(
                                        context,
                                        const Color(0xffffe092),
                                      ),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    _newCardNotice!,
                                    style: TextStyle(
                                      color: gameColor(context, Colors.white),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Tap to view in Cards',
                                    style: TextStyle(
                                      color: gameColor(
                                        context,
                                        const Color(0xfff9db9a),
                                      ),
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
            if (_brokenRoadOwner != null)
              Positioned.fill(child: IgnorePointer(child: _roadBreakOverlay())),
            if (_crownRoadWinner != null)
              Positioned.fill(child: IgnorePointer(child: _crownRoadOverlay())),
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
              Positioned.fill(
                key: ValueKey('match-finale-overlay-${s.seed}'),
                child: _finishOverlay(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roadBreakOverlay() => AnimatedBuilder(
    animation: _roadBreakController,
    builder: (context, child) {
      final t = _roadBreakController.value;
      final fade =
          (t < .12
                  ? t / .12
                  : t > .8
                  ? (1 - t) / .2
                  : 1.0)
              .clamp(0.0, 1.0);
      return Align(
        alignment: const Alignment(0, -.65),
        child: Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(math.sin(t * math.pi * 28) * 12 * (1 - t), t * 14),
            child: Container(
              key: const ValueKey('crown-road-break-animation'),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: gameColor(context, const Color(0xf52e181c)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: gameColor(context, const Color(0xffff756e)),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '💔 CROWN ROAD BROKEN',
                    style: TextStyle(
                      color: gameColor(context, const Color(0xffff8c83)),
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${s.players[_brokenRoadOwner!].id}: $_roadBeforeBreak → $_roadAfterBreak roads'
                    '${_roadAwardLost ? ' · −2 Renown' : ''}',
                  ),
                  const Text('One guard. Your grand road, in pieces.'),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _crownRoadOverlay() => AnimatedBuilder(
    animation: _crownRoadController,
    builder: (context, child) {
      final t = _crownRoadController.value;
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
              key: const ValueKey('crown-road-award-animation'),
              decoration: BoxDecoration(
                color: gameColor(context, const Color(0xf5222b32)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: gameColor(context, const Color(0xffffd680)),
                  width: 2,
                ),
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
                    Text(
                      '🏆 CROWN ROAD!',
                      style: TextStyle(
                        color: gameColor(context, const Color(0xffffde93)),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${s.players[_crownRoadWinner!].id} · +2 Renown',
                      style: TextStyle(
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
                    color: gameColor(context, const Color(0xff183931)),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: gameColor(context, const Color(0xff7fe4b8)),
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
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'The royal property market has collapsed.',
                          style: TextStyle(
                            color: gameColor(context, const Color(0xffbde7d4)),
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
          color: gameColor(
            context,
            const Color(0xff3c0715),
          ).withValues(alpha: .72),
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
                    color: gameColor(context, const Color(0xff1b101b)),
                    border: Border.all(
                      color: gameColor(context, const Color(0xffff6c43)),
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
                        child: Icon(
                          Icons.castle_rounded,
                          color: gameColor(context, const Color(0xffff8861)),
                          size: 84,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        mine
                            ? 'YOUR CITY HAS FALLEN!'
                            : "${_fallenCityOwner!.toUpperCase()}'S CITY HAS FALLEN!",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: gameColor(context, const Color(0xffffd6a3)),
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
                        style: TextStyle(
                          color: gameColor(context, const Color(0xffffb8aa)),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '−$_fallenCityVp VICTORY ${_fallenCityVp == 1 ? 'POINT' : 'POINTS'}',
                        style: TextStyle(
                          color: gameColor(context, const Color(0xffff6555)),
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
    final won = widget.viewingSeat != null
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

  bool get _canFastForward =>
      widget.onFastForward != null && s.phase != MatchPhase.finished;

  Widget _fastForwardButton() => FilledButton.icon(
    key: const ValueKey('fast-forward-bots'),
    onPressed: _skipBotDice || widget.fastForwardingBots
        ? null
        : () {
            setState(() {
              _skipBotDice = true;
              _rollingDice = null;
            });
            widget.onFastForward?.call();
          },
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 42),
      disabledForegroundColor: Theme.of(context).brightness == Brightness.light
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
    ),
    icon: _skipBotDice || widget.fastForwardingBots
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.fast_forward),
    label: Text(
      _skipBotDice || widget.fastForwardingBots
          ? 'Fast-forwarding…'
          : 'Fast-forward bots',
    ),
  );

  Widget _mobileActionsButton() => SizedBox(
    key: _actionsHintTarget,
    width: 128,
    height: 42,
    child: OutlinedButton.icon(
      key: const ValueKey('mobile-open-actions'),
      style: OutlinedButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 13),
        backgroundColor: gameColor(context, const Color(0xf0182a31)),
        foregroundColor: gameColor(context, const Color(0xffe5c183)),
      ),
      onPressed: _openMobileActions,
      icon: const Icon(Icons.layers_outlined),
      label: const Text('Actions'),
    ),
  );

  Widget _mobileLayout(MatchPhase phase) {
    if (_mobilePage != null) {
      return Column(
        children: [
          if (s.tactical == null || widget.observing)
            Material(
              color: gameColor(context, const Color(0xff182a31)),
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
            child: _mobileActionsButton(),
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
                          color: gameColor(context, const Color(0xe014242b)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.waitingMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: gameColor(context, const Color(0xffdce8e9)),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  left: 12,
                  right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _mobileActionsButton(),
                      if (_canFastForward) _fastForwardButton(),
                    ],
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
                      _mobileActionsButton(),
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

  List<Widget> _matchOptions(BuildContext context) => [
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
              style: TextStyle(
                fontSize: 11,
                color: gameColor(context, const Color(0xffa8bfc0)),
              ),
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
      final actingLabel = s.pendingDiscards.isNotEmpty
          ? 'Discard'
          : s.tactical != null
          ? 'Respond'
          : 'Turn';
      final size = MediaQuery.sizeOf(context);
      final portrait = size.height > size.width && bounds.maxWidth < 600;
      final height = portrait
          ? math.max(
              52.0,
              MediaQuery.textScalerOf(context).scale(12) * 1.2 + 18,
            )
          : math.max(
              bounds.maxWidth < 900
                  ? bounds.maxWidth < 720
                        ? 44.0
                        : 52.0
                  : _compact
                  ? 48.0
                  : 52.0,
              MediaQuery.textScalerOf(context).scale(12) * 1.2 +
                  MediaQuery.textScalerOf(context).scale(10) * 1.2 +
                  18,
            );
      // Give large accessibility text full-width cards in the horizontal list.
      final singleColumn =
          portrait &&
          (bounds.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(12) > 15);
      final width = portrait
          ? singleColumn
                ? bounds.maxWidth - 20 - (widget.onLeaveRoom != null ? 48 : 0)
                : (bounds.maxWidth -
                          26 -
                          (widget.onLeaveRoom != null ? 48 : 0)) /
                      2
          : math.max(
              124.0 * MediaQuery.textScalerOf(context).scale(12) / 12,
              (bounds.maxWidth - 50 - (widget.onLeaveRoom != null ? 48 : 0)) /
                      s.players.length -
                  6,
            );
      return Container(
        height: height,
        padding: EdgeInsets.fromLTRB(8, 3, portrait ? 0 : 42, 3),
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
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final i in [
                      viewerSeat,
                      for (var seat = 0; seat < s.players.length; seat++)
                        if (seat != viewerSeat) seat,
                    ])
                      Semantics(
                        label:
                            '${s.players[i].id}, ${MatchEngine.score(s, i)} of 15 Renown${i == winner
                                ? ', winner'
                                : i == s.actingSeat && winner == null
                                ? ', active player'
                                : ''}',
                        child: Tooltip(
                          message: i == viewerSeat
                              ? 'Settings'
                              : '${MatchEngine.score(s, i)} Renown',
                          child: InkWell(
                            onTap: i == viewerSeat ? _openPlayerOptions : null,
                            child: Container(
                              key: ValueKey('player-tile-$i'),
                              width: width,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (i == s.actingSeat && winner == null) ||
                                        i == winner
                                    ? gameColor(
                                        context,
                                        seatColors[i],
                                      ).withValues(alpha: .13)
                                    : gameColor(
                                        context,
                                        const Color(0xff1c2e35),
                                      ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color:
                                      (i == s.actingSeat && winner == null) ||
                                          i == winner
                                      ? gameColor(context, seatColors[i])
                                      : gameColor(
                                          context,
                                          const Color(0xff30434a),
                                        ),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: portrait ? 20 : 29,
                                        height: 40,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Align(
                                              alignment: Alignment.topCenter,
                                              child: Icon(
                                                i == s.actingSeat &&
                                                        winner == null
                                                    ? Icons.flag_rounded
                                                    : Icons.shield_outlined,
                                                size: portrait ? 16 : 20,
                                                color: gameColor(
                                                  context,
                                                  seatColors[i],
                                                ),
                                              ),
                                            ),
                                            if (!portrait &&
                                                MediaQuery.sizeOf(context)
                                                        .width <
                                                    900 &&
                                                !_hasTopActivitySpace)
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                bottom: 0,
                                                height: 21,
                                                child: MatchActivity(
                                                  key: ValueKey(
                                                    'player-emote-$i',
                                                  ),
                                                  state: s,
                                                  viewerSeat: viewerSeat,
                                                  targetSeat: i,
                                                  emotesOnly: true,
                                                  computerSeats:
                                                      widget.computerSeats,
                                                  emote:
                                                      widget.networkEmote ??
                                                      _emote,
                                                  emoteSerial:
                                                      widget.online &&
                                                          widget.onEmote != null
                                                      ? widget
                                                            .networkEmoteSerial
                                                      : _emoteSerial,
                                                  emoteSeat:
                                                      widget.networkEmoteSeat,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(width: portrait ? 3 : 6),
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
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.2,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            if (!portrait &&
                                                i == s.actingSeat &&
                                                winner == null &&
                                                i != winner &&
                                                width < 180)
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  '${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    height: 1.2,
                                                    color: gameColor(
                                                      context,
                                                      seatColors[i],
                                                    ),
                                                  ),
                                                ),
                                              )
                                            else if (!portrait)
                                              Text(
                                                i == winner
                                                    ? 'Winner'
                                                    : i == s.actingSeat &&
                                                          winner == null
                                                    ? '$actingLabel · ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}${s.crownRoadHolder == i ? ' · Road +2' : ''}'
                                                    : s.crownRoadHolder == i
                                                    ? 'Crown road · +2 Renown'
                                                    : 'Realm ${i + 1}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  height: 1.2,
                                                  color:
                                                      i == s.actingSeat &&
                                                          winner == null
                                                      ? gameColor(
                                                          context,
                                                          seatColors[i],
                                                        )
                                                      : gameColor(
                                                          context,
                                                          const Color(
                                                            0xffa6b6ba,
                                                          ),
                                                        ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: portrait
                                            ? 22
                                            : MediaQuery.textScalerOf(context)
                                                      .scale(20) *
                                                  1.4,
                                        child: Text(
                                          '${MatchEngine.score(s, i)}',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: gameColor(
                                              context,
                                              seatColors[i],
                                            ),
                                            fontSize: portrait ? 14 : 20,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (!portrait)
                                        Text(
                                          ' /15',
                                          style: TextStyle(
                                            fontSize: 10,
                                            height: 1.2,
                                            color: gameColor(
                                              context,
                                              const Color(0xffa6b6ba),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (!portrait && !_hasTopActivitySpace)
                                    Positioned.fill(
                                      child: MatchActivity(
                                        key: ValueKey('activity-seat-$i'),
                                        state: s,
                                        viewerSeat: viewerSeat,
                                        targetSeat: i,
                                        showEmotes: false,
                                        fastForwardingBots:
                                            widget.fastForwardingBots,
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
            width: 345,
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
                    child: ListView(children: _matchOptions(dialogContext)),
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
            children: _matchOptions(context),
          ),
        ),
      ),
    );
  }

  double get _instructionHeight => math.max(
    60,
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
    if (event is RecruitGuard) vertex = event.vertex;
    if (event is ActivateGuard) vertex = event.vertex;
    if (event is PromoteGuard) vertex = event.vertex;
    if (event is MoveGuard) vertex = event.to;
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
        child: ValueListenableBuilder<Offset?>(
          valueListenable: _boardHoverPosition,
          builder: (context, hoverPosition, _) => LayoutBuilder(
            builder: (context, box) {
              // Keep pointer motion local to the map, rather than rebuilding the
              // player bar, action panel, and trade calculations on every event.
              // Keep the instruction strip outside the interactive map coordinates.
              final size = Size(box.maxWidth, math.max(1, box.maxHeight));
              final hover = hoverPosition == null
                  ? null
                  : _boardHover(hoverPosition, size);
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
                            _boardHoverPosition.value = event.localPosition,
                        onExit: (_) => _boardHoverPosition.value = null,
                        child: GestureDetector(
                          // A single accessibility tap for the entire canvas
                          // loses the pointer's board coordinates on web.
                          // Retain the descriptive Semantics wrapper above,
                          // but leave coordinate-based taps to the gesture.
                          excludeFromSemantics: true,
                          behavior: HitTestBehavior.opaque,
                          onTapUp:
                              s.tactical == null &&
                                  s.pendingDiscards.isEmpty &&
                                  !widget.observing
                              ? (details) =>
                                    tapBoard(details.localPosition, size)
                              : null,
                          child: CustomPaint(
                            painter: _Painter(
                              s,
                              widget.observing || s.tactical != null
                                  ? _Move.inspect
                                  : move,
                              selectedGuard,
                              devicePixelRatio: View.of(context)
                                  .devicePixelRatio,
                              boardOrigin: () =>
                                  (context.findRenderObject()! as RenderBox)
                                      .localToGlobal(Offset.zero),
                              showTargets:
                                  !widget.observing &&
                                  !_choosingCardTarget &&
                                  viewerSeat == s.actingSeat &&
                                  s.tactical == null,
                              hoveredRoad:
                                  hoverPosition != null &&
                                      !widget.observing &&
                                      !_choosingCardTarget &&
                                      viewerSeat == s.actingSeat &&
                                      s.tactical == null &&
                                      (move == _Move.road ||
                                          (move == _Move.inspect &&
                                              s.phase == MatchPhase.actions))
                                  ? _roadNear(
                                      hoverPosition,
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
                              roadBreak: _roadBreakController,
                              brokenRoads: _brokenRoadRoute,
                              roadBreakVertex: _roadBreakVertex,
                              roadCelebration: _crownRoadController,
                              highlightedRoads: _crownRoadRoute,
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
                                      left: (hoverPosition!.dx + 16).clamp(
                                        8.0,
                                        math.max(8.0, size.width - 268),
                                      ),
                                      top: (hoverPosition.dy + 24).clamp(
                                        8.0,
                                        math.max(8.0, size.height - 100),
                                      ),
                                      child: IgnorePointer(
                                        child: Container(
                                          key: const ValueKey(
                                            'board-hover-hint',
                                          ),
                                          width: 250,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: gameColor(
                                              context,
                                              const Color(0xff101e25),
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: gameColor(
                                                context,
                                                const Color(0xffd6bd80),
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            hover,
                                            style: TextStyle(
                                              color: gameColor(
                                                context,
                                                const Color(0xfff5ead3),
                                              ),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!widget.fastForwardingBots)
                                    BoardEventEffects(
                                      eventIndex: s.events.length,
                                      event: s.events.isEmpty
                                          ? null
                                          : s.events.last,
                                      anchor: _eventAnchor(size),
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
                color: gameColor(context, const Color(0xf014242b)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: gameColor(context, const Color(0xff365159)),
                ),
              ),
              child: Semantics(
                label:
                    'Raid defence. ${s.raidInterval - s.reaverPressure.clamp(0, s.raidInterval)} of ${s.raidInterval} rounds until attack. ${MatchEngine.defenceStrength(s) + s.invasionAid} defence versus ${MatchEngine.invasionStrength(s)} bandit strength.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Raid Defense',
                      style: TextStyle(
                        color: gameColor(context, const Color(0xffefd6a3)),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Raid ${s.raidInterval - s.reaverPressure.clamp(0, s.raidInterval)} / ${s.raidInterval} rounds',
                      style: TextStyle(fontSize: 11, height: 1.15),
                    ),
                    Text(
                      'Defence ${MatchEngine.defenceStrength(s) + s.invasionAid} / ${MatchEngine.invasionStrength(s)}',
                      style: TextStyle(fontSize: 11, height: 1.15),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (MediaQuery.sizeOf(context).height >
              MediaQuery.sizeOf(context).width &&
          MediaQuery.sizeOf(context).width < 600)
        Positioned(top: 8, right: 1, child: _emoteButton()),
      if (s.dice != null)
        Positioned(
          top: 52,
          right: 12,
          child: Semantics(
            label: 'Last dice total ${s.dice}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: gameColor(context, const Color(0xf014242b)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: gameColor(context, const Color(0xff61716a)),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.casino_outlined,
                    size: 18,
                    color: gameColor(context, const Color(0xffe5c183)),
                  ),
                  Text(
                    '${s.dice}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: gameColor(context, const Color(0xffefd6a3)),
                    ),
                  ),
                ],
              ),
            ),
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
              selectedGuard = null;
            }),
            icon: const Icon(Icons.close),
          ),
        ),
    ],
  );

  Widget _desktopFooter(double railWidth) => Container(
    constraints: BoxConstraints(minHeight: _instructionHeight),
    decoration: BoxDecoration(
      color: gameColor(context, const Color(0xff14242b)),
      border: Border(
        top: BorderSide(color: gameColor(context, const Color(0xff34464a))),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _instruction,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: gameColor(context, const Color(0xffefd6a3)),
                        ),
                      ),
                      Text(
                        _hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: gameColor(context, const Color(0xffabbfc2)),
                        ),
                      ),
                    ],
                  ),
                ),
                if (choice != _Move.inspect && phaseAllowsChoice)
                  IconButton(
                    tooltip: 'Cancel selection',
                    onPressed: () => setState(() {
                      choice = _Move.inspect;
                      selectedGuard = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: railWidth,
          child: _canFastForward
              ? null
              : Visibility(
                  visible:
                      s.tactical == null &&
                      !widget.observing &&
                      s.phase != MatchPhase.finished,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: _turnButton(),
                  ),
                ),
        ),
      ],
    ),
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
                onTap: () {
                  setState(() {
                    _tab = index;
                    if (index == 2) _unseenCard = false;
                    if (index != 0) {
                      choice = _Move.inspect;
                      selectedGuard = null;
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
                                ? gameColor(context, const Color(0xff2c4145))
                                : Colors.transparent,
                            gameColor(
                              context,
                              const Color(0xff786039),
                              light: const Color(0xffe4cda3),
                            ),
                            _cardsTabPulse * 0.7,
                          )
                        : _tab == index
                        ? gameColor(context, const Color(0xff2c4145))
                        : null,
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: _tab == index
                            ? gameColor(context, const Color(0xffe5c183))
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
                                ? gameColor(context, const Color(0xffefd6a3))
                                : gameColor(context, const Color(0xffa6b6ba)),
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
                              gameColor(context, const Color(0xffffdb7d)),
                              gameColor(context, Colors.white),
                              _cardsTabPulse,
                            ),
                          ),
                        ),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color: _tab == index
                              ? gameColor(context, const Color(0xffefd6a3))
                              : gameColor(context, const Color(0xffa6b6ba)),
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
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: gameColor(context, const Color(0xffefd6a3)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: gameColor(context, const Color(0xffabbfc2)),
          ),
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
      message: '$name · $cost',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size.fromHeight(52),
          alignment: Alignment.centerLeft,
          disabledForegroundColor:
              Theme.of(context).brightness == Brightness.light
              ? gameColor(context, const Color(0xffabbfc2))
              : null,
          backgroundColor: choice == action
              ? gameColor(context, const Color(0xff354e4b))
              : gameColor(context, const Color(0xff20343c)),
          side: BorderSide(
            color: choice == action
                ? gameColor(context, const Color(0xffe5c183))
                : gameColor(context, const Color(0xff40565b)),
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
                selectedGuard = null;
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
                  Text(name, style: TextStyle(fontWeight: FontWeight.w700)),
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
                          child: ResourceLabel(
                            label,
                            adaptive: true,
                            style: TextStyle(
                              fontSize: 11,
                              color: gameColor(
                                context,
                                const Color(0xffabbfc2),
                              ),
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
            style: TextStyle(
              color: gameColor(context, const Color(0xffe5c183)),
            ),
          ),
          Text(
            s.players[s.actingSeat].id,
            key: const ValueKey('acting-player-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            widget.waitingMessage ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  List<Widget> _visiblePanelContents(MatchPhase phase) {
    // Keep the whole panel browseable off-turn (including card details,
    // trades and realm information). Individual gameplay actions enforce
    // turn ownership; incoming trade replies remain available when allowed.
    return _panelContents(
      widget.observing ? MatchPhase.actions : phase,
      selectedTab: _tab,
    );
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
            color: gameColor(context, seatColors[s.active]),
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
          Text(
            phase == MatchPhase.setupRoad
                ? 'Tap an edge beside your new settlement.'
                : 'Tap a glowing mark on the map.',
            style: TextStyle(
              fontSize: 12,
              color: gameColor(context, const Color(0xffabbfc2)),
            ),
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
                'Recruit Guard',
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
                'Activate Guard',
                _costLabel(MatchEngine.activateCost),
                s.guards.keys.any((v) => MatchEngine.legalActivate(s, v)),
              ),
              _buildAction(
                _Move.promote,
                Icons.upgrade,
                'Upgrade Guard',
                'Sentinel → Warden: ${_costLabel(MatchEngine.promotionCost(GuardRank.sentinel))}\nWarden → Champion: ${_costLabel(MatchEngine.promotionCost(GuardRank.warden))}',
                s.guards.keys.any((v) => MatchEngine.legalPromote(s, v)),
              ),
              _buildAction(
                _Move.guardMove,
                Icons.open_with,
                'Move Guard',
                'Free · active Guard, once per turn\nOne edge along your road; displace a weaker enemy Guard',
                s.guards.keys.any(
                  (v) =>
                      s.guards[v]!.owner == s.active &&
                      MatchEngine.legalGuardDestinations(s, v).isNotEmpty,
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
                      'Active Guards and Fortifications defend the realm.',
                    ),
                ],
              ),
            ),
          ),

        if (phase == MatchPhase.bandit && s.pendingDiscards.isEmpty)
          Text(
            'Choose a different hex. Any theft and response will be resolved before building.',
            style: TextStyle(
              fontSize: 12,
              color: gameColor(context, const Color(0xffabbfc2)),
            ),
          ),
      ];
    }
    if (tab == 1) {
      return [
        TradeMarket(
          state: s,
          computerSeats: widget.computerSeats,
          hiddenIncomingOfferId: _incomingTradeOpen
              ? _incomingDialogOfferId
              : null,
          allowOffers: !widget.observing,
          allowCounters: !widget.observing || widget.tradeReplyAllowed,
          privateOpponentHands: widget.online,
          onBank: exchange,
          onOffer: offer,
          onCounter: offer,
          onEvent: send,
          viewerSeat: viewerSeat,
        ),
        const SizedBox(height: 8),
        Text(
          "Paper funds Innovation upgrades; cloth funds Commerce; coin funds Governance.",
          style: TextStyle(
            color: gameColor(context, const Color(0xffbac9cc)),
            fontSize: 12,
          ),
        ),
      ];
    }
    if (tab == 2) {
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
        child: ResourceLabel(
          '${s.players[viewerSeat].stores[Resource.paper] ?? 0} paper · '
          '${s.players[viewerSeat].stores[Resource.cloth] ?? 0} cloth · '
          '${s.players[viewerSeat].stores[Resource.coin] ?? 0} coin',
          adaptive: true,
          style: TextStyle(
            fontSize: 12,
            color: gameColor(context, const Color(0xffbac9cc)),
          ),
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
                final terrain = terrainLabel(track.sourceLand);
                final rolls = MatchEngine.developmentHexes(
                  s,
                  track,
                  viewerSeat,
                ).map((hex) => hex.productionNumber!).toList()..sort();
                final cost = level == 5
                    ? <Resource, int>{}
                    : MatchEngine.developmentCost(s, track, level + 1);
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
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              rolls.isEmpty
                                  ? 'Requires your Town or Capital on a $terrain hex'
                                  : '$terrain hexes · ${rolls.join(', ')}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              level < 5
                                  ? 'Next: ${track.tiers[level]}'
                                  : 'Complete',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              _developmentEffect(
                                s,
                                track,
                                level == 5 ? 5 : level + 1,
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                color: gameColor(
                                  context,
                                  const Color(0xffadc4c6),
                                ),
                              ),
                            ),
                            if (level < 5) ...[
                              const SizedBox(height: 5),
                              ResourceLabel(
                                'Cost: ${_costLabel(cost)}',
                                adaptive: true,
                                style: TextStyle(fontSize: 12),
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
    ];
  }

  VoidCallback? get _turnActionCallback =>
      widget.observing || (widget.online && s.actingSeat != viewerSeat)
      ? null
      : switch (s.phase) {
          MatchPhase.roll => () {
            final (a, b) = widget.online ? (0, 0) : MatchEngine.expectedDice(s);
            send(RollDice(a, b));
          },
          MatchPhase.actions => () => send(const EndTurn()),
          MatchPhase.invasion => () => send(const ResolveInvasion()),
          _ => null,
        };

  Widget _turnButton({bool compact = false}) =>
      s.phase == MatchPhase.setupVillage ||
          s.phase == MatchPhase.setupRoad ||
          s.phase == MatchPhase.bandit
      ? const SizedBox.shrink()
      : Tooltip(
          message: s.phase == MatchPhase.roll
              ? 'Roll'
              : s.phase == MatchPhase.actions
              ? 'Done'
              : _instruction,
          key: _turnHintTarget,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: Size(0, compact ? 42 : 48),
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 10)
                  : null,
              textStyle: compact
                  ? Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontSize: 13)
                  : null,
              disabledBackgroundColor: gameColor(
                context,
                const Color(0xff425963),
                light: const Color(0xffeee9df),
              ),
              disabledForegroundColor: gameColor(
                context,
                const Color(0xfff4eee2),
                light: const Color(0xff405458),
              ),
              backgroundColor: gameColor(context, const Color(0xffe5c183)),
              foregroundColor: gameColor(context, const Color(0xff28271e)),
            ),
            onPressed: _turnActionCallback,
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
                  ? 'Roll'
                  : s.phase == MatchPhase.invasion
                  ? compact
                        ? 'Resolve'
                        : 'Resolve Invasion'
                  : s.phase == MatchPhase.actions
                  ? 'Done'
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
              style: TextStyle(
                fontFamily: 'NotoSans',
                color: gameColor(context, const Color(0xff172b33)),
              ),
            ),
          ),
        );

  Widget _resourceTray({bool anchorHarvest = false}) {
    final tight = _compact || MediaQuery.sizeOf(context).width < 900;
    final horizontal = anchorHarvest && MediaQuery.sizeOf(context).width >= 900;
    final portrait =
        MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width &&
        MediaQuery.sizeOf(context).width < 600;
    final tiles = <Widget>[
      for (final r in Resource.values)
        Tooltip(
          message: '${r.displayName}: ${inventoryOwner.stores[r] ?? 0}',
          child: GestureDetector(
            onTap: s.phase == MatchPhase.actions && !widget.observing
                ? () => _resourceTrade(r)
                : null,
            child: ResourceRewardPulse(
              key: ValueKey('resource-tile-${r.name}'),
              deferAnimation: _rollingDice != null,
              anchor: anchorHarvest ? _resourceAnchors[r] : null,
              count: inventoryOwner.stores[r] ?? 0,
              seat: widget.viewingSeat ?? viewerSeat,
              color: gameColor(context, _goodColor(r)),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal ? 8 : 4,
                  vertical: horizontal ? 4 : 0,
                ),
                decoration: BoxDecoration(
                  color: gameColor(
                    context,
                    const Color(0xff20323a),
                    light: const Color(0xffeee9df),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    top: BorderSide(
                      color: gameColor(context, _goodColor(r)),
                      width: 3,
                    ),
                  ),
                ),
                child: Flex(
                  direction: horizontal ? Axis.horizontal : Axis.vertical,
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
                    if (!horizontal) ResourceIcon(r, size: tight ? 20 : 27),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
    return Container(
      height:
          math.max(
            horizontal ? 58 : (tight ? 49 : 66),
            MediaQuery.textScalerOf(context).scale(tight ? 14 : 17) * 1.2 +
                (horizontal ? 0 : (tight ? 20 : 27)) +
                (tight ? 13 : 19),
          ) *
          (portrait ? 2 : 1),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: tight ? 4 : 6),
      decoration: BoxDecoration(
        color: gameColor(context, const Color(0xff101e25)),
        border: Border(
          top: BorderSide(color: gameColor(context, const Color(0xff34464a))),
        ),
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
                    icon: Icon(
                      Icons.palette_outlined,
                      size: 20,
                      color: gameColor(context, const Color(0xffe5c183)),
                    ),
                  ),
                  if (portrait)
                    Expanded(
                      child: Column(
                        children: [
                          for (var row = 0; row < 2; row++) ...[
                            if (row > 0) const SizedBox(height: 4),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final tile
                                      in tiles.skip(row * 4).take(4))
                                    Expanded(child: tile),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    for (final tile in tiles) Expanded(child: tile),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _developmentEffect(MatchState s, StrategyDeck track, int tier) {
    final basic = track.sourceLand.produces!.displayName;
    final commodity = track.commodity.displayName;
    final balance = s.balance;

    return switch ((track, tier)) {
      (_, 1) => 'Towns and Capitals produce 1 $commodity in place of 1 $basic.',
      (StrategyDeck.innovation, 2) when balance.stoneworksTier == 2 =>
        'Build roads for 1 wood each.',
      (StrategyDeck.innovation, 2) => 'Unlock tier 2 Innovation draws.',
      (StrategyDeck.innovation, 3) =>
        '${balance.stoneworksTier == 3 ? 'Build roads for 1 wood each. ' : ''}Drought relief starts after 2 dry rolls.',
      (StrategyDeck.innovation, 4) =>
        'Drought relief gives your scarcest basic resource in stock.',
      (StrategyDeck.innovation, 5) =>
        '+1 invasion defence. Convert a second $basic to $commodity.',
      (StrategyDeck.commerce, 2) => '${balance.marketRate}:1 bank trades.',
      (StrategyDeck.commerce, 3) =>
        'Get 2 cloth when trading for cloth. Safe hand size +2.',
      (StrategyDeck.commerce, 4) => '${balance.guildRate}:1 bank trades.',
      (StrategyDeck.commerce, 5) =>
        'Get ${balance.bazaarGoods} goods per bank trade. Convert a second $basic to $commodity.',
      (StrategyDeck.governance, 2) => '+1 invasion defence.',
      (StrategyDeck.governance, 3) =>
        'Protect hand goods from raids. Safe hand size +2.',
      (StrategyDeck.governance, 4) => 'Recruit Guards for 1 sheep each.',
      (StrategyDeck.governance, 5) =>
        '+1 more invasion defence. Convert a second $basic to $commodity.',
      _ => throw StateError('Invalid development tier: $tier'),
    };
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
        if (MatchEngine.canDevelop(funded, track))
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
  void didUpdateWidget(covariant _TradeComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind && widget.kind == _TradeKind.bank) {
      final s = widget.state;
      if ((s.current.stores[give] ?? 0) <
          MatchEngine.tradeRate(s, s.active, give)) {
        final payable = Resource.values.where(
          (good) =>
              (s.current.stores[good] ?? 0) >=
              MatchEngine.tradeRate(s, s.active, good),
        );
        if (payable.isNotEmpty) {
          give = payable.first;
          if (give == take) {
            take = Resource.values.firstWhere((good) => good != give);
          }
        }
      }
      bankTimes = 1;
    }
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
    final gives = {...extraGive, if (giveCount > 0) give: giveCount};
    final wants = {...extraTake, if (takeCount > 0) take: takeCount};
    final valid =
        (bank ||
            (canPayTrade(s.current.stores, gives) &&
                gives.keys.every((g) => !wants.containsKey(g)))) &&
        give != take &&
        available >= required &&
        (!bank || bankAvailable >= receipt * bankTimes) &&
        (bank || (giveCount > 0 && takeCount > 0 && target != s.active));
    Widget seatMarker(int seat) =>
        Icon(Icons.circle, color: seatColors[seat], size: 12);

    Widget recipientLabel(int seat) => Row(
      children: [
        seatMarker(seat),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'To ${s.players[seat].id}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

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
                                    child: recipientLabel(i),
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
                              child: recipientLabel(i),
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
              style: TextStyle(
                fontSize: 12,
                color: gameColor(context, const Color(0xffabbfc2)),
              ),
            ),
            const SizedBox(height: 11),
            if (!bank && widget.counter == null) ...[
              Text(
                'OFFER TO',
                style: TextStyle(
                  color: gameColor(context, const Color(0xffe5c183)),
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
                        avatar: seatMarker(i),
                        onSelected: (_) => setState(() => target = i),
                      ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
          if (widget.onKindSelected != null && !compactLandscape)
            SizedBox(
              height: 20,
              child: Text(
                bank
                    ? 'Rate $rate:$receipt · Bank stock: $bankAvailable'
                    : 'Tap + to add goods. Tap − to take one back.',
                key: const ValueKey('trade-summary-stable'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: gameColor(context, const Color(0xffabbfc2)),
                ),
              ),
            ),
          if (widget.onKindSelected != null && !compactLandscape)
            Visibility(
              visible: bank,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: Padding(
                padding: EdgeInsets.zero,
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
                    Text(
                      '$bankTimes',
                      key: const ValueKey('bank-bundle-count'),
                    ),
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
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              void updateBundle(Map<Resource, int> next, bool giving) {
                setState(() {
                  final primary = giving ? give : take;
                  final extras = giving ? extraGive : extraTake;
                  final replacement = next.containsKey(primary) || next.isEmpty
                      ? primary
                      : next.keys.first;
                  extras
                    ..clear()
                    ..addAll(next)
                    ..remove(replacement);
                  if (giving) {
                    give = replacement;
                    giveCount = next[replacement] ?? 0;
                  } else {
                    take = replacement;
                    takeCount = next[replacement] ?? 0;
                  }
                });
              }

              return TradePicker(
                holdings: s.current.stores,
                gives: bank ? {give: required} : gives,
                wants: bank ? {take: receipt * bankTimes} : wants,
                bank: bank,
                bankStock: s.bank,
                rates: {
                  for (final good in Resource.values)
                    good: MatchEngine.tradeRate(s, s.active, good),
                },
                receipts: {
                  for (final good in Resource.values)
                    good:
                        (commerce >= 5 ||
                            (commerce >= 3 && good == Resource.cloth)
                        ? 2
                        : 1),
                },
                onChange: (good, giving, delta) {
                  if (bank) {
                    setState(() {
                      if (giving) {
                        give = good;
                      } else {
                        take = good;
                      }
                      bankTimes = 1;
                    });
                    return;
                  }
                  final next = Map<Resource, int>.of(giving ? gives : wants);
                  final count = (next[good] ?? 0) + delta;
                  if (count <= 0) {
                    next.remove(good);
                  } else {
                    next[good] = count;
                  }
                  updateBundle(next, giving);
                },
              );
            },
          ),
          const SizedBox(height: 8),
          if (!valid)
            Text(
              !bank && (gives.isEmpty || wants.isEmpty)
                  ? 'Add goods in both the Give and Get columns.'
                  : give == take
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    key: const ValueKey('trade-offer-preview'),
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      ResourceLabel(
                        bank
                            ? 'Give $required ${give.displayName}'
                            : 'Give ${gives.isEmpty ? "…" : tradeBundleText(gives)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 16),
                      ResourceLabel(
                        bank
                            ? 'Get ${receipt * bankTimes} ${take.displayName}'
                            : 'Get ${wants.isEmpty ? "…" : tradeBundleText(wants)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FilledButton(
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
                ],
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
            'Exhaust one active Guard to prevent the theft.',
      TacticalKind.governance =>
        'A targeted Governance card is pending. '
            'Spend the matching countercard to cancel it.',
      TacticalKind.invasion when state.balance.raidAidCap > 0 =>
        'The table can pledge up to ${state.balance.raidAidCap} defence per raid. '
            'Wheat adds 1 and ore adds up to 2.',
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
          style: TextStyle(
            color: gameColor(context, const Color(0xffe5c183)),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(detail, style: TextStyle(fontSize: 12)),
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
            label: const Text('Intercept with Guard'),
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
                  label: ResourceLabel(
                    'Pledge 1 ${good.displayName}',
                    showNames: true,
                  ),
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
          style: TextStyle(fontSize: 11),
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

  // Portrait has room for a more top-down table. Change the hex geometry
  // rather than scaling the canvas, so artwork and pieces stay isotropic.
  bool get isPortrait => size.height > size.width * 1.10;
  // Wide phone screens have unused water to the left and right. Expand
  // the table projection there while keeping circular markers isotropic.
  double get horizontalFactor => isPortrait
      ? 1.0
      : horizontalScale +
            .20 * ((size.aspectRatio - 2.0) / 1.0).clamp(0.0, 1.0);
  double get verticalFactor => isPortrait ? 1.10 : verticalScale;

  double get radius {
    if (isPortrait) {
      return math.min(
        size.width / (9.4 * horizontalFactor),
        math.max(1, size.height - 112) / (8 * verticalFactor),
      );
    }
    // Local dock badges need no remote gutters. Leave enough space for
    // the outermost pieces and let badges hug the coast at the boundary.
    return math.min(
      size.width / (9.2 * horizontalFactor),
      math.max(1, size.height - 28) / (8 * verticalFactor),
    );
  }

  Offset get center => Offset(size.width / 2, size.height / 2);
  Offset vertex(BoardVertex p) =>
      center +
      Offset(p.x * radius * horizontalFactor, p.y * radius * verticalFactor);
  Offset tile(HexCoord p) =>
      center +
      Offset(
        math.sqrt(3) * radius * (p.q + p.r / 2) * horizontalFactor,
        1.5 * radius * p.r * verticalFactor,
      );
}

class _Painter extends CustomPainter {
  _Painter(
    this.state,
    this.mode,
    this.selectedGuard, {
    required this.devicePixelRatio,
    required this.boardOrigin,
    required this.roadReveal,
    required this.roadBreak,
    required this.brokenRoads,
    required this.roadBreakVertex,
    required this.roadCelebration,
    required this.highlightedRoads,
    required this.numberPulse,
    required this.banditBlock,
    this.humiliatedBanditTile,
    this.showTargets = true,
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
           roadBreak,
           numberPulse,
           banditBlock,
           resourceIconStyle,
           resourceIconsRevision,
           _capitalImage,
         ]),
       );
  final MatchState state;
  final double devicePixelRatio;
  final Offset Function() boardOrigin;
  final bool showTargets;
  final int? hoveredRoad;
  final Set<int> cardRoadTargets, cardVertexTargets, cardTileTargets;
  final _Move mode;
  final int? selectedGuard;
  final int? animatedRoad;
  final int? animatedRoadStart;
  final Animation<double> roadReveal;
  final Animation<double> roadBreak;
  final List<int> brokenRoads;
  final int? roadBreakVertex;
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
              radius * math.cos(angle) * g.horizontalFactor,
              radius * math.sin(angle) * g.verticalFactor,
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
      _terrain(canvas, Offset.zero, radius, tile.land, g);
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
        // Keep the production number unobscured; shame the bandit whenever
        // the blocked number rolls or a guard stops a theft.
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
    if (roadBreak.value > 0 && roadBreak.value < 1 && roadBreakVertex != null) {
      final t = roadBreak.value;
      final paint = Paint()
        ..color = const Color(0xffff554e).withValues(alpha: (1 - t) * .9)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round;
      for (final id in brokenRoads) {
        final edge = state.topology.edges[id];
        final a = g.vertex(state.topology.vertices[edge.a]);
        final b = g.vertex(state.topology.vertices[edge.b]);
        final drift = Offset(0, 18 * t * t);
        canvas.drawLine(a + drift, Offset.lerp(a, b, .42)! + drift, paint);
        canvas.drawLine(Offset.lerp(a, b, .58)! + drift, b + drift, paint);
      }
      final c = g.vertex(state.topology.vertices[roadBreakVertex!]);
      final radius = 12 + 22 * t;
      canvas.drawCircle(
        c,
        radius,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawLine(c + const Offset(-8, -14), c + const Offset(3, 0), paint);
      canvas.drawLine(c + const Offset(3, 0), c + const Offset(-3, 4), paint);
      canvas.drawLine(c + const Offset(-3, 4), c + const Offset(8, 14), paint);
    }
    final legal = <int>{
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
          for (final v in state.guards.keys)
            if (MatchEngine.legalActivate(state, v)) v,
        },
        _Move.promote => {
          for (final v in state.guards.keys)
            if (MatchEngine.legalPromote(state, v)) v,
        },
        _Move.guardMove =>
          selectedGuard == null
              ? {
                  for (final v in state.guards.keys)
                    if (state.guards[v]!.owner == state.active &&
                        state.guards[v]!.active &&
                        state.guards[v]!.actedTurn != state.turnSerial &&
                        MatchEngine.legalGuardDestinations(state, v).isNotEmpty)
                      v,
                }
              : MatchEngine.legalGuardDestinations(
                  state,
                  selectedGuard!,
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
      final capitalImage = _capitalImage.value;
      final usesCapitalArt =
          site.structure == Structure.capital && capitalImage != null;
      final width = switch (site.structure) {
        Structure.village => 15.0,
        Structure.town => 21.0,
        Structure.capital => capitalImage == null ? 28.0 : 34.0,
      };
      final center = c + Offset(0, usesCapitalArt ? -4 : 2);
      final Rect bounds;
      if (usesCapitalArt) {
        // Align the whole sprite to physical pixels so opposite edges and
        // windows sample the source image at matching offsets.
        final origin = boardOrigin();
        final pixelSize = (width * devicePixelRatio).round();
        final topLeft =
            (origin + center) * devicePixelRatio -
            Offset(pixelSize / 2, pixelSize / 2);
        bounds = Rect.fromLTWH(
          topLeft.dx.round() / devicePixelRatio - origin.dx,
          topLeft.dy.round() / devicePixelRatio - origin.dy,
          pixelSize / devicePixelRatio,
          pixelSize / devicePixelRatio,
        );
      } else {
        bounds = Rect.fromCenter(
          center: center,
          width: width,
          height: site.structure == Structure.village ? width : width * .75,
        );
      }
      if (state.fortified.contains(v.id)) {
        final halo = bounds.inflate(10);
        canvas.drawOval(
          halo,
          Paint()
            ..shader = const RadialGradient(
              colors: [Color(0xfffff1ae), Color(0xe6ffcb54), Color(0x00ffab26)],
              stops: [0, .48, 1],
            ).createShader(halo),
        );
      }
      if (usesCapitalArt) {
        canvas.drawImageRect(
          capitalImage,
          Rect.fromLTWH(
            0,
            0,
            capitalImage.width.toDouble(),
            capitalImage.height.toDouble(),
          ),
          bounds,
          _capitalPaints[site.owner],
        );
      } else {
        final building = RRect.fromRectAndRadius(
          bounds,
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
        }
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
    for (final entry in state.guards.entries) {
      final guard = entry.value;
      final c = g.vertex(state.topology.vertices[entry.key]);
      canvas.drawCircle(c, 9, Paint()..color = const Color(0xff182a32));
      canvas.drawCircle(
        c,
        7,
        Paint()
          ..color = guard.active
              ? seatColors[guard.owner]
              : const Color(0xff879699),
      );
      _label(canvas, '${guard.rank.strength}', c, 11, const Color(0xff102028));
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
    // A dock is a local feature of its own coastal edge. Keep the badge
    // immediately offshore rather than moving it into a remote side gutter.
    for (final dock in state.topology.docks) {
      final a = g.vertex(state.topology.vertices[dock.edge.a]);
      final b = g.vertex(state.topology.vertices[dock.edge.b]);
      final tile = g.tile(state.board.tiles[dock.edge.tiles.single].position);
      final label = TextPainter(
        text: TextSpan(
          text: dock.resource == null ? '3:1' : '2:1',
          style: const TextStyle(
            fontFamily: 'NotoSans',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xffffe5b2),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final layout = coastalDockBadge(
        size: size,
        a: a,
        b: b,
        tileCenter: tile,
        hasResource: dock.resource != null,
      );
      final badge = layout.badge;
      final gold = Paint()
        ..color = const Color(0xffe5c58a)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(layout.shore, layout.connection, gold);
      // Mark the actual trading edge, without covering the ownership road.
      canvas.drawCircle(
        layout.shore,
        3,
        Paint()..color = const Color(0xff182a31),
      );
      canvas.drawCircle(layout.shore, 1.8, gold);
      final frame = RRect.fromRectAndRadius(badge, const Radius.circular(5));
      canvas.drawRRect(frame, Paint()..color = const Color(0xff182a31));
      canvas.drawRRect(
        frame,
        Paint()
          ..color = const Color(0xffc7ac78)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8,
      );
      if (dock.resource case final resource?) {
        paintResourceIcon(
          canvas,
          Offset(badge.left + 10, badge.center.dy),
          14,
          resource,
        );
      }
      final textCenter =
          badge.center + Offset(dock.resource == null ? 0 : 8, 0);
      label.paint(
        canvas,
        textCenter - Offset(label.width / 2, label.height / 2),
      );
      label.dispose();
    }
  }

  // Geometric marks are fixed decorations for each terrain.
  // They never read or advance the match's random event stream.
  void _terrain(Canvas canvas, Offset c, double r, Land land, BoardGeometry g) {
    final resource = switch (land) {
      Land.woodland => Resource.wood,
      Land.clayBeds => Resource.brick,
      Land.fields => Resource.wheat,
      Land.meadows => Resource.wool,
      Land.ridges => Resource.ore,
      Land.barren => null,
    };
    if (resource == null) return;
    for (final side in [-1.0, 1.0]) {
      paintResourceIcon(
        canvas,
        c + Offset(side * r * .60 * g.horizontalFactor, 0),
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

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final g = BoardGeometry(size);
    return [
      for (final dock in state.topology.docks)
        CustomPainterSemantics(
          rect: coastalDockBadge(
            size: size,
            a: g.vertex(state.topology.vertices[dock.edge.a]),
            b: g.vertex(state.topology.vertices[dock.edge.b]),
            tileCenter: g.tile(
              state.board.tiles[dock.edge.tiles.single].position,
            ),
            hasResource: dock.resource != null,
          ).badge,
          properties: SemanticsProperties(
            label: '${dock.label} port',
            textDirection: TextDirection.ltr,
          ),
        ),
    ];
  };

  @override
  bool shouldRebuildSemantics(_Painter old) =>
      !identical(old.state.topology, state.topology);

  bool _sameTargets(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  bool shouldRepaint(_Painter old) =>
      !identical(old.state, state) ||
      old.devicePixelRatio != devicePixelRatio ||
      old.mode != mode ||
      old.showTargets != showTargets ||
      old.hoveredRoad != hoveredRoad ||
      !_sameTargets(old.cardRoadTargets, cardRoadTargets) ||
      !_sameTargets(old.cardVertexTargets, cardVertexTargets) ||
      !_sameTargets(old.cardTileTargets, cardTileTargets) ||
      old.selectedGuard != selectedGuard ||
      old.animatedRoad != animatedRoad ||
      old.roadReveal != roadReveal ||
      old.banditBlock != banditBlock ||
      old.humiliatedBanditTile != humiliatedBanditTile;
}
