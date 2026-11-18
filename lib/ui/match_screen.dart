// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/advanced.dart';
import '../engine/board.dart';
import '../engine/game.dart';
import '../engine/match.dart';
import '../replay_codes.dart';
import 'strategy_hand.dart';
import 'labels.dart';
import 'resource_harvest.dart';
import 'resource_icon.dart';
import 'trade_market.dart';
import 'trade_leg.dart';
import 'game_notice.dart';
import 'match_activity.dart';
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
    this.automationError,
    this.onResumeAutomation,
    this.online = false,
    this.onlineView,
    this.viewingSeat,
    this.computerSeats = const <int>{},
    this.visibleSeat,
    this.waitingMessage,
    this.onHome,
    this.onRules,
  });
  final MatchState state;
  final ValueChanged<MatchEvent> onEvent;
  final bool observing;
  final String? automationError;
  final VoidCallback? onResumeAutomation;
  final bool online;
  final Map<String, dynamic>? onlineView;
  final int? viewingSeat;
  final Set<int> computerSeats;
  final int? visibleSeat;
  final String? waitingMessage;
  final VoidCallback? onHome, onRules;
  @override
  State<MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<MatchView> with TickerProviderStateMixin {
  final _resourceAnchors = {for (final r in Resource.values) r: LayerLink()};
  _Move choice = _Move.inspect;
  int? selectedKnight;
  Size? _boardSize;
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
  bool _townHintDismissed = false;

  Future<void> _loadHints() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hintsEnabled = prefs.getBool('gameplay_hints_enabled') ?? true;
      _hintsLoaded = true;
    });
  }

  Future<void> _setHintsEnabled(bool enabled) async {
    setState(() => _hintsEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gameplay_hints_enabled', enabled);
  }

  bool get _showTownHint =>
      _hintsLoaded &&
      _hintsEnabled &&
      !_townHintDismissed &&
      !widget.observing &&
      s.phase == MatchPhase.actions &&
      s.tactical == null &&
      s.active == viewerSeat &&
      s.players[viewerSeat].developments.values.every((level) => level == 0) &&
      s.sites.values.any(
        (site) =>
            site.owner == viewerSeat && site.structure != Structure.village,
      );

  Widget _townProductionHint(bool mobile) => Container(
    key: const ValueKey('town-production-hint'),
    color: const Color(0xff243b43),
    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Text(
            'A Town alone gives basic goods. In Realm, build Scriptorium '
            '(woodland → paper), Loomhouse (meadows → cloth), or Mint House '
            '(ridges → coin). Each costs 1 wheat + 1 ore. '
            'Then collect on matching rolls.',
            style: TextStyle(fontSize: 12, color: Color(0xffdce8e9)),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            _townHintDismissed = true;
            _tab = 3;
            if (mobile) _mobilePage = -1;
          }),
          child: const Text('Realm'),
        ),
        IconButton(
          tooltip: 'Dismiss hint for this game',
          onPressed: () => setState(() => _townHintDismissed = true),
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  );
  late final AnimationController _numberPulseController;

  @override
  void initState() {
    super.initState();
    unawaited(loadResourceIcons());
    unawaited(_loadHints());
    _turnClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          s.phase == MatchPhase.finished ||
          s.tactical != null ||
          // A dialog or target picker is open above this match route.
          // Never consume a local turn while the player is interacting
          // with a blocking overlay.
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      if (_secondsLeft > 0) setState(() => _secondsLeft--);
      if (_secondsLeft == 0 &&
          !widget.online &&
          !widget.observing &&
          _expiredEventCount != s.events.length) {
        final event = MatchEngine.idleEvent(s);
        if (event != null) {
          _expiredEventCount = s.events.length;
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
    _numberPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
      value: 1,
    );
  }

  MatchState get s => widget.state;
  PlayerState get inventoryOwner => s.players[widget.viewingSeat ?? viewerSeat];
  int get viewerSeat => widget.visibleSeat ?? widget.viewingSeat ?? s.active;
  _Move get move => switch (s.phase) {
    MatchPhase.setupVillage => _Move.village,
    MatchPhase.setupRoad => _Move.road,
    MatchPhase.bandit => _Move.bandit,
    _ => choice,
  };
  void send(MatchEvent event) {
    widget.onEvent(event);
    setState(() {
      choice = _Move.inspect;
      selectedKnight = null;
    });
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
      builder: (context) => AlertDialog(
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
      builder: (context) => AlertDialog(
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

  Future<void> tapBoard(Offset tap, Size size) async {
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
          await _confirmRoad(best);
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
          builder: (context) => AlertDialog(
            title: const Text('Bandit · steal one good?'),
            content: const Text(
              'Choose a neighbour. The good is drawn from their hand using the saved seed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, -1),
                child: const Text('Take none'),
              ),
              for (final n in victims)
                TextButton(
                  onPressed: () => Navigator.pop(context, n),
                  child: Text(s.players[n].id),
                ),
            ],
          ),
        );
        if (chosen != null && mounted) {
          send(MoveBandit(best, victim: chosen == -1 ? null : chosen));
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
            builder: (dialogContext) => AlertDialog(
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
        }) {
          if ((tap - g.vertex(s.topology.vertices[vertex])).distance >
              math.min(18, g.radius * .3)) {
            continue;
          }
          if (!mounted) return;
          final upgrade = s.sites.containsKey(vertex);
          final event = await showDialog<MatchEvent>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                upgrade ? 'Upgrade settlement?' : 'Build settlement?',
              ),
              content: Text(
                upgrade
                    ? _upgradeCostLabel()
                    : _costLabel(MatchEngine.villageCost),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    upgrade ? UpgradeSite(vertex) : PlaceVillage(vertex),
                  ),
                  child: Text(
                    upgrade ? 'Upgrade settlement' : 'Build settlement',
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
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          // Keep the sheet compact on normal landscape phones, but leave
          // enough vertical room for at least one option at large text scales.
          height: math.min(
            MediaQuery.sizeOf(context).height *
                (MediaQuery.textScalerOf(context).scale(1) > 1.2 ? .76 : .52),
            math.max(190, 62 + options.length * 52.0),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  'Choose legal board target',
                  style: Theme.of(context).textTheme.titleLarge,
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
  }) async {
    final event = await showDialog<MatchEvent>(
      context: context,
      barrierColor: fromTray ? Colors.black38 : null,
      builder: (_) => StatefulBuilder(
        builder: (context, updateKind) {
          return Dialog(
            // Leave the inventory visible under quick trades opened from
            // the resource tray, rather than covering it with a full-screen
            // second dialog.
            insetPadding: fromTray
                ? const EdgeInsets.fromLTRB(12, 8, 12, 72)
                : const EdgeInsets.all(12),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 660,
              height: MediaQuery.sizeOf(context).height * (fromTray ? .75 : .9),
              child: _TradeComposer(
                state: s,
                kind: kind,
                counter: counter,
                initialGive: initialGive,
                onKindSelected: counter == null
                    ? (value) => updateKind(() => kind = value)
                    : null,
              ),
            ),
          );
        },
      ),
    );
    if (mounted && event != null) send(event);
  }

  final _panelScroll = List.generate(4, (_) => ScrollController());
  bool _panelExpanded = false;

  bool get _compact => MediaQuery.sizeOf(context).height < 350;

  int _tab = 0;
  // null: map; -1: full-screen actions.
  int? _mobilePage;

  void _openMobileCategory(int tab) {
    setState(() {
      _tab = tab;
      _mobilePage = -1;
    });
    if (tab == 1 && s.phase == MatchPhase.actions && s.active == viewerSeat) {
      exchange();
    }
  }

  void _openMobileActions() => setState(() {
    _tab = 0;
    _mobilePage = -1;
  });

  void _backMobile() => setState(() => _mobilePage = null);

  @override
  void dispose() {
    _turnClock?.cancel();
    _roadController.dispose();
    _numberPulseController.dispose();
    for (final controller in _panelScroll) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (s.seed != oldWidget.state.seed ||
        s.events.length < oldWidget.state.events.length) {
      _townHintDismissed = false;
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
    if (oldWidget.state.turnSerial != s.turnSerial ||
        oldWidget.state.active != s.active ||
        (widget.online && oldWidget.state.events.length != s.events.length)) {
      _secondsLeft = 90;
      _expiredEventCount = null;
    }
    if (oldWidget.state.active != s.active ||
        oldWidget.state.phase != s.phase) {
      choice = _Move.inspect;
      selectedKnight = null;
      if (s.phase != MatchPhase.actions) _tab = 0;
      _mobilePage = null;
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
          MatchPhase.roll => 'Your turn begins',
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
          MatchPhase.roll => 'Roll the dice to collect this turn’s production',
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
    final phase = s.phase;
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
                  if (_showTownHint) _townProductionHint(mobile),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        if (mobile) return _mobileLayout(phase);
                        final desktop =
                            bounds.maxWidth >= 1200 && bounds.maxHeight >= 550;
                        final railWidth = desktop
                            ? (bounds.maxWidth * .25).clamp(320.0, 420.0)
                            : _panelExpanded
                            ? math.min(460.0, bounds.maxWidth * .72)
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
                                      Row(
                                        children: [
                                          Expanded(child: _tabs()),
                                          if (!desktop)
                                            IconButton(
                                              tooltip: _panelExpanded
                                                  ? 'Narrow action panel'
                                                  : 'Expand action panel',
                                              onPressed: () => setState(() {
                                                _panelExpanded =
                                                    !_panelExpanded;
                                              }),
                                              icon: Icon(
                                                _panelExpanded
                                                    ? Icons.close_fullscreen
                                                    : Icons.open_in_full,
                                              ),
                                            ),
                                        ],
                                      ),
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
                                                  'panel-$_tab-${s.active}',
                                                ),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: _compact ? 8 : 12,
                                                  vertical: _compact ? 4 : 12,
                                                ),
                                                children: [
                                                  if (widget.observing)
                                                    _waitingStatus(),
                                                  ..._visiblePanelContents(
                                                    phase,
                                                  ),
                                                  if (widget.observing)
                                                    ..._matchOptions(),
                                                ],
                                              ),
                                            ),
                                    ),
                                    if (s.tactical == null &&
                                        !widget.observing &&
                                        s.phase != MatchPhase.finished)
                                      _turnAction(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (!mobile || _mobilePage == null)
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
            // Center activity notices below the top controls on every screen.
            Positioned(
              top:
                  MediaQuery.paddingOf(context).top +
                  (mobile ? (_mobilePage == null ? 118 : 72) : 74),
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: mobile ? 190 : 260),
                  child: MatchActivity(
                    state: s,
                    viewerSeat: viewerSeat,
                    computerSeats: widget.computerSeats,
                  ),
                ),
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
          _mobilePageHeader(),
          if (s.tactical == null || widget.observing)
            Material(color: const Color(0xff182a31), child: _tabs()),
          Expanded(child: _mobileActionHub()),
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
          if (widget.automationError != null)
            FilledButton(
              onPressed: widget.onResumeAutomation,
              child: const Text('Resume computer'),
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

  Widget _mobilePageHeader() => Container(
    color: const Color(0xff182a31),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back to map',
          onPressed: _backMobile,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        Expanded(
          child: Text('Actions', style: Theme.of(context).textTheme.titleLarge),
        ),
        if (s.phase != MatchPhase.finished)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: 'Turn timer pauses while a dialog is open',
              child: Text(
                '${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(color: Color(0xffe5c183)),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _hintSetting() => SwitchListTile(
    title: const Text('Gameplay hints'),
    subtitle: const Text('Show tips when learning a game'),
    value: _hintsEnabled,
    onChanged: _hintsLoaded ? _setHintsEnabled : null,
  );

  List<Widget> _matchOptions() => [
    _hintSetting(),
    if (widget.onRules != null)
      ListTile(
        leading: const Icon(Icons.menu_book),
        title: const Text('Rules'),
        onTap: widget.onRules,
      ),
    if (widget.onHome != null)
      ListTile(
        leading: const Icon(Icons.home_outlined),
        title: const Text('Home'),
        onTap: widget.onHome,
      ),
  ];

  Widget _mobileActionHub() => ListView(
    controller: _panelScroll[_tab],
    key: const ValueKey('mobile-action-hub'),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    children: [
      if (s.tactical != null && !widget.observing)
        SizedBox(
          height: 450,
          child: _TacticalPanel(state: s, onEvent: send, online: widget.online),
        )
      else ...[
        if (widget.observing) _waitingStatus(),
        if (_tab == 0 && s.phase == MatchPhase.actions)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Choose a piece, then tap a highlighted spot on the map.',
              style: TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
            ),
          ),
        ..._visiblePanelContents(s.phase),
      ],
      const SizedBox(height: 12),
      ..._matchOptions(),
    ],
  );

  Widget _playerBar() => LayoutBuilder(
    builder: (context, bounds) {
      final winner = MatchEngine.winner(s);
      final height = math.max(
        bounds.maxWidth < 900
            ? 44.0
            : _compact
            ? 48.0
            : 52.0,
        MediaQuery.textScalerOf(context).scale(12) * 1.2 +
            MediaQuery.textScalerOf(context).scale(10) * 1.2 +
            18,
      );
      final width = math.max(
        128.0 * MediaQuery.textScalerOf(context).scale(12) / 12,
        (bounds.maxWidth - 50) / s.players.length - 6,
      );
      return Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(8, 3, 42, 3),
        decoration: const BoxDecoration(
          color: Color(0xff14242b),
          border: Border(bottom: BorderSide(color: Color(0xff34464a))),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < s.players.length; i++)
                Semantics(
                  label:
                      '${s.players[i].id}, ${MatchEngine.score(s, i)} of 15 Victory Points${i == winner
                          ? ', winner'
                          : i == s.active
                          ? ', active player'
                          : ''}',
                  child: Container(
                    width: width,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
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
                    child: Row(
                      children: [
                        Icon(
                          i == s.active
                              ? Icons.flag_rounded
                              : Icons.shield_outlined,
                          size: 20,
                          color: seatColors[i],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
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
                        Text(
                          '${MatchEngine.score(s, i)}',
                          style: TextStyle(
                            color: seatColors[i],
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
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
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  double get _instructionHeight => math.max(
    50,
    MediaQuery.textScalerOf(context).scale(15) * 1.2 +
        MediaQuery.textScalerOf(context).scale(11) * 1.2 +
        12,
  );

  String get _compactInstruction {
    if (s.phase == MatchPhase.roll) return 'Roll for goods';
    if (s.phase == MatchPhase.finished) return 'Match complete';
    if (s.phase == MatchPhase.actions && move == _Move.inspect) {
      return 'Your realm';
    }
    return _instruction;
  }

  String? get _compactHint => switch (s.phase) {
    MatchPhase.setupVillage => 'Tap a glowing junction',
    MatchPhase.setupRoad => 'Tap glowing edge',
    MatchPhase.bandit => 'Choose another hex',
    MatchPhase.invasion =>
      s.invasionAid > 0
          ? 'Emergency aid +${s.invasionAid}'
          : 'Review shared defence',
    MatchPhase.actions when move != _Move.inspect => 'Tap highlighted target',
    _ => null,
  };

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
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: ClipRect(
                  child: Semantics(
                    key: const ValueKey('realm-map'),
                    label: 'Realm map. $_instruction. $_hint',
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
                          animatedRoad: _animatedRoad,
                          animatedRoadStart: _animatedRoadStart,
                          roadReveal: _roadReveal,
                          numberPulse: _numberPulseController,
                        ),
                        child: SizedBox.expand(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              BoardEventEffects(
                                eventIndex: s.events.length,
                                event: s.events.isEmpty ? null : s.events.last,
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
            );
          },
        ),
      ),
      // Keep phase guidance and fleet status in one opaque, bounded HUD.
      // Separate absolute-positioned labels previously drew through each
      // other and across the upper-left map tiles.
      Positioned(
        top: 8,
        left: 10,
        child: IgnorePointer(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: mobileFullscreen
                  ? math.min(160, MediaQuery.sizeOf(context).width * .30)
                  : 230,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xf014242b),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xff365159)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.phase == MatchPhase.invasion
                        ? 'INVASION · ROUND ${s.round}'
                        : 'ROUND ${s.round}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xffc4d2cf),
                      fontSize: 10,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InvasionMeter(state: s),
                  if (mobileFullscreen) ...[
                    const SizedBox(height: 5),
                    Text(
                      _compactInstruction,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: Color(0xffefd6a3),
                      ),
                    ),
                    if (_compactHint != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _compactHint!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          color: Color(0xffc6d5d5),
                        ),
                      ),
                    ],
                  ],
                ],
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
            tooltip: 'Choose board target from list',
            onPressed: chooseTarget,
            icon: const Icon(Icons.format_list_numbered),
          ),
        ),
      if (mobileFullscreen && choice != _Move.inspect && phaseAllowsChoice)
        Positioned(
          top: availableTargets.isNotEmpty ? 94 : 48,
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
                    tooltip: 'Choose board target from list',
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

  Widget _tabs() => Row(
    children: [
      for (final (index, icon, label) in [
        (0, Icons.construction_rounded, 'Build'),
        (1, Icons.swap_horiz_rounded, 'Trade'),
        (2, Icons.style_outlined, 'Cards'),
        (3, Icons.castle_outlined, 'Realm'),
      ])
        Expanded(
          child: Tooltip(
            message: label,
            child: InkWell(
              onTap: () {
                if (index == 1 &&
                    !widget.observing &&
                    s.phase == MatchPhase.actions &&
                    s.active == viewerSeat) {
                  exchange();
                }
                setState(() {
                  _tab = index;
                  if (index != 0) {
                    choice = _Move.inspect;
                    selectedKnight = null;
                  }
                });
              },
              child: Container(
                constraints: BoxConstraints(minHeight: _compact ? 48 : 54),
                decoration: BoxDecoration(
                  color: _tab == index ? const Color(0xff2c4145) : null,
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
                    Icon(
                      icon,
                      size: 20,
                      color: _tab == index
                          ? const Color(0xffefd6a3)
                          : const Color(0xffa6b6ba),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: enabled
          ? () => setState(() {
              choice = action;
              selectedKnight = null;
              _panelExpanded = false;
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
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  cost,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xffabbfc2),
                  ),
                ),
              ],
            ),
          ),
          if (choice == action)
            const Icon(Icons.check_circle_outline, size: 20),
        ],
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

  Widget _waitingStatus() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.automationError != null
              ? 'Computer paused'
              : widget.online
              ? 'Waiting for players'
              : 'Computer turn',
          style: const TextStyle(color: Color(0xffe5c183)),
        ),
        Text(s.players[s.tactical?.responder ?? s.active].id),
        if (widget.waitingMessage?.isNotEmpty ?? false)
          Text(widget.waitingMessage!, style: const TextStyle(fontSize: 12)),
        if (widget.automationError != null) ...[
          Text(widget.automationError!),
          FilledButton(
            onPressed: widget.onResumeAutomation,
            child: const Text('Resume computer'),
          ),
        ],
      ],
    ),
  );

  List<Widget> _visiblePanelContents(MatchPhase phase) {
    final contents = _panelContents(
      widget.observing ? MatchPhase.actions : phase,
      selectedTab: _tab,
    );
    if (!widget.observing) return contents;
    return [
      for (final child in contents)
        ExcludeFocus(
          child: AbsorbPointer(child: Opacity(opacity: .5, child: child)),
        ),
    ];
  }

  List<Widget> _panelContents(MatchPhase phase, {int? selectedTab}) {
    final tab = selectedTab ?? _tab;
    if (tab == 0) {
      return [
        if (phase != MatchPhase.actions)
          _heading(
            _instruction,
            phase == MatchPhase.actions
                ? 'Choose a piece, then tap the map.'
                : phase == MatchPhase.setupVillage ||
                      phase == MatchPhase.setupRoad
                ? 'Place your starting pieces to begin.'
                : _hint,
          ),
        if (phase != MatchPhase.actions && _mobilePage != null)
          _backToBoardAction(),
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
        if (phase == MatchPhase.actions) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAction(
                _Move.road,
                Icons.route,
                'Road',
                _costLabel(MatchEngine.effectiveRoadCost(s)),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Knights & Defense',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (var seat = 0; seat < s.players.length; seat++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${s.players[seat].id}: ${s.knights.values.where((k) => k.owner == seat && k.active).fold<int>(0, (total, k) => total + k.rank.strength)} active strength · ${s.knights.values.where((k) => k.owner == seat && !k.active).length} inactive',
                  ),
                ),
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
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InvasionMeter(state: s),
                  const SizedBox(height: 8),
                  Text('Expected result: ${MatchEngine.invasionForecast(s)}'),
                  if (s.tactical != null)
                    const Text('Emergency aid can still change this result.'),
                  if (s.invasionAid > 0)
                    Text(
                      'Emergency aid +' +
                          s.invasionAid.toString() +
                          ' is included in the defence preview.',
                    ),
                  const Text(
                    'All active Knights and Fortifications defend. '
                    'A failed defence damages the highest-scoring Town '
                    'or Capital; a sole leading Knight defender may earn '
                    "Guardian's Honour.",
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

        if (phase == MatchPhase.roll)
          const Text(
            'Production goes to every eligible settlement. Outcomes use your saved match seed.',
            style: TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
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
          onBank: exchange,
          onOffer: offer,
          onCounter: offer,
          onEvent: send,
          viewerSeat: viewerSeat,
          onReturnToBoard: _mobilePage == null
              ? null
              : () => setState(() => _mobilePage = null),
        ),
        const SizedBox(height: 12),
        _resourceTray(),
        const Text(
          "Paper funds Innovation upgrades; cloth funds Commerce; coin funds Governance.",
          style: TextStyle(color: Color(0xffbac9cc), fontSize: 12),
        ),
      ];
    }
    if (tab == 2) {
      if (phase != MatchPhase.actions) {
        return [
          _heading(
            'Strategy cards',
            phase == MatchPhase.roll
                ? 'Roll the dice before playing your strategy cards.'
                : 'Resolve the current event before playing cards.',
          ),
          if (_mobilePage != null) _backToBoardAction(),
        ];
      }
      return [
        StrategyHand(
          state: s,
          onEvent: send,
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
      if (MediaQuery.sizeOf(context).width >= 900) _hintSetting(),
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          'Paper (${s.current.stores[Resource.paper] ?? 0}) · '
          'Cloth (${s.current.stores[Resource.cloth] ?? 0}) · '
          'Coin (${s.current.stores[Resource.coin] ?? 0})  —  '
          '${s.sites.values.any((site) => site.owner == s.active && site.structure != Structure.village) ? 'Choose a track below.' : 'Upgrade a village to a Town first (2 wheat · 3 ore).'}',
          style: const TextStyle(fontSize: 12, color: Color(0xffbac9cc)),
        ),
      ),
      if (s.current.level(StrategyDeck.innovation) < 5 &&
          MatchEngine.canDevelop(s, StrategyDeck.innovation))
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const ValueKey('quick-innovation-development'),
            onPressed: MatchEngine.canDevelop(s, StrategyDeck.innovation)
                ? () => send(const DevelopTown(StrategyDeck.innovation))
                : null,
            icon: const Icon(Icons.auto_awesome_outlined, size: 17),
            label: Text(
              s.current.level(StrategyDeck.innovation) == 0
                  ? 'Unlock paper production'
                  : (MatchEngine.developmentCost(
                              s,
                              StrategyDeck.innovation,
                              s.current.level(StrategyDeck.innovation) + 1,
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
                final level = s.current.level(track);
                final cost = level == 5
                    ? <Resource, int>{}
                    : MatchEngine.developmentCost(s, track, level + 1);
                final missing = cost.entries
                    .where(
                      (entry) =>
                          (s.current.stores[entry.key] ?? 0) < entry.value,
                    )
                    .map(
                      (entry) =>
                          '${entry.value - (s.current.stores[entry.key] ?? 0)} ${entry.key.name}',
                    )
                    .join(', ');
                final ownsTown = s.sites.values.any(
                  (site) =>
                      site.owner == s.active &&
                      site.structure != Structure.village,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${track.name.toUpperCase()} · $level/5',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            level < 5
                                ? 'Next: ${track.tiers[level]}'
                                : 'Complete',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            level == 0
                                ? 'Unlocks ${track.commodity.name} from Towns beside ${terrainLabel(track.sourceLand)}.'
                                : 'Your ${terrainLabel(track.sourceLand)} Towns produce ${track.commodity.name} instead of one basic good.',
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
                            onPressed: MatchEngine.canDevelop(s, track)
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
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text('Reaver Fleet arrival ${s.reaverPressure}/3'),
      InvasionMeter(state: s),
      if (s.lastInvasion.isNotEmpty) Text(s.lastInvasion),
      Text(
        'First Capital: ${s.firstCapitalOwner == null ? 'unclaimed' : s.players[s.firstCapitalOwner!].id}',
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Standings', style: Theme.of(context).textTheme.titleMedium),
          if (!widget.online)
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: MatchEngine.exportReplay(s)),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(GameNotice.snackBar('Replay copied'));
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy replay'),
            ),
        ],
      ),
      if (!widget.online)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: ReplayCodes.compact(MatchEngine.exportReplay(s)),
                ),
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  GameNotice.snackBar(
                    'Share code copied; it contains every private hand.',
                  ),
                );
              }
            },
            icon: const Icon(Icons.share_outlined),
            label: const Text('Copy compact replay code'),
          ),
        ),
      for (var i = 0; i < s.players.length; i++)
        Row(
          children: [
            Icon(Icons.flag, color: seatColors[i], size: 19),
            const SizedBox(width: 6),
            Expanded(child: Text(s.players[i].id)),
            Text(
              '${MatchEngine.score(s, i)} VP · Road ${MatchEngine.longestRoad(s, i)}',
            ),
            if (s.longestRoadHolder == i)
              const Tooltip(
                message: 'Longest road · +2 VP',
                child: Icon(Icons.military_tech),
              ),
          ],
        ),
      if (s.dice != null)
        Text(
          widget.online
              ? 'Last dice: ${s.dice} · Event ${widget.onlineView?['eventCount']}'
              : 'Last dice: ${s.dice} · Event ${s.events.length}',
        ),
      if (selectedTab == null) ..._matchOptions(),
    ];
  }

  Widget _turnAction() => Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: _compact ? 2 : 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xff34464a))),
    ),
    child: SizedBox(width: double.infinity, child: _turnButton()),
  );

  Widget _turnButton({bool compact = false}) => FilledButton.icon(
    style: FilledButton.styleFrom(
      minimumSize: Size(0, compact ? 42 : 48),
      padding: compact ? const EdgeInsets.symmetric(horizontal: 10) : null,
      textStyle: compact ? const TextStyle(fontSize: 13) : null,
      disabledBackgroundColor: const Color(0xff425963),
      disabledForegroundColor: const Color(0xfff4eee2),
      backgroundColor: const Color(0xffe5c183),
      foregroundColor: const Color(0xff28271e),
    ),
    onPressed: switch (s.phase) {
      MatchPhase.roll => () {
        final (a, b) = widget.online ? (0, 0) : MatchEngine.expectedDice(s);
        send(RollDice(a, b));
      },
      MatchPhase.actions => () => send(const EndTurn()),
      MatchPhase.invasion => () => send(const ResolveInvasion()),
      MatchPhase.setupVillage ||
      MatchPhase.setupRoad ||
      MatchPhase.bandit => availableTargets.isNotEmpty ? chooseTarget : null,
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
      style: const TextStyle(fontFamily: 'NotoSans', color: Color(0xff172b33)),
    ),
  );

  Widget _resourceTray({bool anchorHarvest = false}) {
    final tight = _compact || MediaQuery.sizeOf(context).width < 900;
    final horizontal = anchorHarvest && MediaQuery.sizeOf(context).width >= 900;
    return Container(
      height: math.max(
        horizontal ? 49 : (tight ? 49 : 66),
        MediaQuery.textScalerOf(context).scale(tight ? 14 : 17) * 1.2 +
            (horizontal ? 0 : (tight ? 20 : 27)) +
            (tight ? 13 : 19),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: tight ? 4 : 6),
      decoration: const BoxDecoration(
        color: Color(0xff101e25),
        border: Border(top: BorderSide(color: Color(0xff34464a))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Choose resource icons',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
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
                message: '${r.name}: ${inventoryOwner.stores[r] ?? 0}',
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
                    color: _goodColor(r),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xff20323a),
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          top: BorderSide(color: _goodColor(r), width: 3),
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
      cost.entries.map((e) => '${e.value} ${e.key.name}').join(' · ');

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

/// A focused dialog composes a trade while the table remains in place.
class _TradeComposer extends StatefulWidget {
  const _TradeComposer({
    required this.state,
    required this.kind,
    this.counter,
    this.initialGive,
    this.onKindSelected,
  });
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
  late int giveCount;
  late int takeCount;
  void _selectUsefulExchange() {
    final s = widget.state;
    final stores = s.current.stores;
    final costs = [
      MatchEngine.villageCost,
      MatchEngine.effectiveRoadCost(s),
      MatchEngine.townCost,
      MatchEngine.capitalCost,
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
    if (incomplete.isEmpty) return;
    final cost = incomplete.first;
    final needed = cost.entries.where((e) => (stores[e.key] ?? 0) < e.value);
    final receivable = needed.where((e) => (s.bank[e.key] ?? 0) > 0);
    final chosen = receivable.isNotEmpty ? receivable.first : needed.first;
    take = chosen.key;
    takeCount = chosen.value - (stores[take] ?? 0);
    final candidates = Resource.values.where((good) => good != take).toList();
    int spare(Resource good) =>
        (stores[good] ?? 0) -
        (cost[good] ?? 0) -
        (widget.kind == _TradeKind.bank
            ? MatchEngine.tradeRate(s, s.active, good)
            : 1);
    candidates.sort((a, b) => spare(b).compareTo(spare(a)));
    give = candidates.first;
  }

  @override
  void initState() {
    super.initState();
    final trade = widget.counter;
    final s = widget.state;
    target = trade?.proposer ?? (s.active + 1) % s.players.length;
    give = trade?.want ?? Resource.wood;
    take = trade?.give ?? Resource.wool;
    giveCount = trade?.wantCount ?? 1;
    takeCount = trade?.giveCount ?? 1;
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
    final required = bank ? rate : giveCount;
    final available = s.current.stores[give] ?? 0;
    final bankAvailable = s.bank[take] ?? 0;
    final valid =
        give != take &&
        available >= required &&
        (!bank || bankAvailable >= receipt) &&
        (bank || (giveCount > 0 && takeCount > 0 && target != s.active));
    final title = bank
        ? 'Bank exchange'
        : widget.counter == null
        ? 'Standing offer'
        : 'Counteroffer';
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: widget.onKindSelected == null ? 48 : 40,
        title: Text(title),
        leading: IconButton(
          tooltip: 'Close trade',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        children: [
          if (widget.onKindSelected != null) ...[
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
                if (!bank) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButton<int>(
                      value: target,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: [
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
              ],
            ),
            const SizedBox(height: 8),
          ] else ...[
            Text(
              bank
                  ? 'Rate $rate:$receipt · Bank stock: $bankAvailable'
                  : 'Only ${s.players[target].id} can accept. Private hands stay hidden.',
              style: const TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
            ),
            const SizedBox(height: 11),
            if (!bank && widget.counter == null) ...[
              const Text(
                'CHOOSE A PLAYER',
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
          if (bank)
            Text(
              'Rate $rate:$receipt · Bank stock: $bankAvailable',
              style: const TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final givePanel = TradeLeg(
                title: 'YOU GIVE',
                hint: bank ? 'Pay the bank' : 'Give when accepted',
                compact: widget.onKindSelected != null,
                resource: give,
                count: required,
                available: available,
                holdings: s.current.stores,
                showCount: !bank,
                onResource: (v) => setState(() => give = v),
                onCount: (v) => setState(() => giveCount = v),
              );
              final takePanel = TradeLeg(
                title: 'YOU RECEIVE',
                hint: bank ? 'From the bank' : 'Request from your rival',
                compact: widget.onKindSelected != null,
                resource: take,
                holdings: bank ? s.bank : null,
                count: bank ? receipt : takeCount,
                showCount: !bank,
                highlight: true,
                onResource: (v) => setState(() => take = v),
                onCount: (v) => setState(() => takeCount = v),
              );
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
                    ? 'Exchange $rate ${give.name} for $receipt ${take.name}.'
                    : 'Offer $giveCount ${give.name} for $takeCount ${take.name} to ${s.players[target].id}.',
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
                  : bank && bankAvailable < receipt
                  ? 'Bank stock is too low.'
                  : 'Check the trade terms.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: widget.onKindSelected == null
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
                            ? BankExchange(give, take)
                            : ProposeTrade(
                                target,
                                give,
                                giveCount,
                                take,
                                takeCount,
                                counterOf: widget.counter?.id,
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
        if (w.kind == TacticalKind.invasion) InvasionMeter(state: state),
        if (w.kind == TacticalKind.invasion)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Expected outcome without more aid',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Text(MatchEngine.invasionForecast(state)),
            ],
          ),
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
                  label: Text('Pledge 1 ${good.name}'),
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
  double get radius => math.min(
    size.width / (9.2 * horizontalScale),
    size.height / (8.6 * verticalScale),
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
    required this.numberPulse,
    this.animatedRoad,
    this.animatedRoadStart,
  }) : super(
         repaint: Listenable.merge([
           roadReveal,
           numberPulse,
           resourceIconStyle,
           resourceIconsRevision,
         ]),
       );
  final MatchState state;
  final _Move mode;
  final int? selectedKnight;
  final int? animatedRoad;
  final int? animatedRoadStart;
  final Animation<double> roadReveal;
  final Animation<double> numberPulse;

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
      if (i == state.banditTile) {
        canvas.drawCircle(
          c,
          radius * .25,
          Paint()..color = const Color(0xff262d37),
        );
        _label(canvas, 'B', c, radius * .23, Colors.white);
      }
    }
    final legalRoads = mode == _Move.road
        ? MatchEngine.legalEdges(state).toSet()
        : <int>{};
    for (final dock in state.topology.docks) {
      final a = g.vertex(state.topology.vertices[dock.edge.a]);
      final b = g.vertex(state.topology.vertices[dock.edge.b]);
      final middle = (a + b) / 2;
      final outward = middle - size.center(Offset.zero);
      final projected = middle + outward / outward.distance * (g.radius * .38);
      final label = Offset(
        projected.dx.clamp(40.0, size.width - 40),
        projected.dy.clamp(9.0, size.height - 9),
      );
      canvas.drawLine(
        a,
        label,
        Paint()
          ..color = const Color(0xffc7ac78)
          ..strokeWidth = 2,
      );
      canvas.drawLine(
        b,
        label,
        Paint()
          ..color = const Color(0xffc7ac78)
          ..strokeWidth = 2,
      );
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
      text.paint(canvas, label - Offset(text.width / 2, text.height / 2));
    }
    for (final e in state.topology.edges) {
      final owner = state.roads[e.id];
      if (owner == null && !legalRoads.contains(e.id)) continue;
      final reversed = e.id == animatedRoad && animatedRoadStart == e.b;
      final a = g.vertex(state.topology.vertices[reversed ? e.b : e.a]);
      final b = g.vertex(state.topology.vertices[reversed ? e.a : e.b]);
      final building =
          owner != null && e.id == animatedRoad && roadReveal.value < 1;
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
          ..color = owner == null ? const Color(0xffafffe3) : seatColors[owner]
          ..strokeWidth = owner == null ? 5 : 6
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
    final legal = switch (mode) {
      _Move.inspect => {
        ...MatchEngine.legalVertices(state),
        ...MatchEngine.legalUpgrades(state),
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
                      MatchEngine.legalKnightDestinations(state, v).isNotEmpty)
                    v,
              }
            : MatchEngine.legalKnightDestinations(
                state,
                selectedKnight!,
              ).toSet(),
      _ => <int>{},
    };
    // Every junction is legal at the start of a match. Use restrained
    // markers so that dozens of bright dots do not overpower the hexes.
    final setupVillage = state.phase == MatchPhase.setupVillage;
    for (final v in state.topology.vertices) {
      final c = g.vertex(v);
      if (legal.contains(v.id)) {
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
      final width = site.structure == Structure.village
          ? 15.0
          : site.structure == Structure.town
          ? 21.0
          : 25.0;
      final building = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c + const Offset(0, 2),
          width: width,
          height: width * .75,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(building, Paint()..color = const Color(0xff20313b));
      canvas.drawRRect(
        building.deflate(2),
        Paint()..color = seatColors[site.owner],
      );
      final roof = Path()
        ..moveTo(c.dx - width * .56, c.dy - width * .22)
        ..lineTo(c.dx, c.dy - width * .68)
        ..lineTo(c.dx + width * .56, c.dy - width * .22);
      canvas.drawPath(
        roof,
        Paint()
          ..color = seatColors[site.owner]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      if (site.structure == Structure.capital) {
        canvas.drawCircle(
          c + const Offset(0, -16),
          3.5,
          Paint()..color = const Color(0xffffd77e),
        );
      }
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
      canvas.drawCircle(
        c + const Offset(0, 15),
        9,
        Paint()..color = const Color(0xff182a32),
      );
      canvas.drawCircle(
        c + const Offset(0, 15),
        7,
        Paint()
          ..color = knight.active
              ? seatColors[knight.owner]
              : const Color(0xff879699),
      );
      _label(
        canvas,
        '${knight.rank.strength}',
        c + const Offset(0, 15),
        11,
        const Color(0xff102028),
      );
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

  @override
  bool shouldRepaint(_Painter old) =>
      !identical(old.state, state) ||
      old.mode != mode ||
      old.selectedKnight != selectedKnight ||
      old.animatedRoad != animatedRoad ||
      old.roadReveal != roadReveal;
}
