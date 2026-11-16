// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/advanced.dart';
import '../engine/board.dart';
import '../engine/game.dart';
import '../engine/match.dart';
import '../replay_codes.dart';
import 'strategy_hand.dart';
import 'labels.dart';
import 'dice_roll.dart';
import 'trade_feedback.dart';
import 'invasion_feedback.dart';

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
  Color(0xff76a696),
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
    this.waitingMessage,
  });
  final MatchState state;
  final ValueChanged<MatchEvent> onEvent;
  final bool observing;
  final String? automationError;
  final VoidCallback? onResumeAutomation;
  final bool online;
  final Map<String, dynamic>? onlineView;
  final int? viewingSeat;
  final String? waitingMessage;
  @override
  State<MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<MatchView> {
  _Move choice = _Move.inspect;
  int? selectedKnight;
  Size? _boardSize;
  MatchState get s => widget.state;
  PlayerState get inventoryOwner => s.players[widget.viewingSeat ?? s.active];
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
      int? best;
      var distance = double.infinity;
      for (final id in MatchEngine.legalEdges(s)) {
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
          best = id;
        }
      }
      if (best != null && distance <= math.max(18, g.radius * .33)) {
        send(PlaceRoad(best));
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
      final selected = s.board.tiles.reduce(
        (a, b) =>
            (tap - g.tile(a.position)).distance <
                (tap - g.tile(b.position)).distance
            ? a
            : b,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${terrainLabel(selected.land)} · Number ${selected.productionNumber?.toString() ?? '—'}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
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
          height: math.min(
            MediaQuery.sizeOf(context).height * .65,
            76 + options.length * 56.0,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
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
                    minVerticalPadding: 12,
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

  Future<void> exchange() => _openTrade(_TradeKind.bank);

  Future<void> offer([TradeProposal? counter]) =>
      _openTrade(_TradeKind.player, counter: counter);

  Future<void> _openTrade(_TradeKind kind, {TradeProposal? counter}) async {
    final event = await showDialog<MatchEvent>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 660,
          height: MediaQuery.sizeOf(context).height * .9,
          child: _TradeComposer(state: s, kind: kind, counter: counter),
        ),
      ),
    );
    if (mounted && event != null) send(event);
  }

  final _panelScroll = List.generate(4, (_) => ScrollController());
  bool _panelExpanded = false;

  bool get _compact => MediaQuery.sizeOf(context).height < 350;

  int _tab = 0;
  final _camera = TransformationController();

  @override
  void dispose() {
    _camera.dispose();
    for (final controller in _panelScroll) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final result = latestTradeFeedback(s);
    if (s.events.length > oldWidget.state.events.length &&
        result != null &&
        s.events
            .skip(oldWidget.state.events.length)
            .any((e) => e is RespondTrade)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(result)));
      });
    }
    if (oldWidget.state.active != s.active ||
        oldWidget.state.phase != s.phase) {
      choice = _Move.inspect;
      selectedKnight = null;
      if (s.phase != MatchPhase.actions) _tab = 0;
    }
  }

  String get _instruction => widget.observing
      ? widget.online
            ? 'Waiting for players'
            : 'Watching the next move'
      : s.tactical != null
      ? 'A response is pending'
      : switch (s.phase) {
          MatchPhase.setupVillage => 'Found your realm',
          MatchPhase.setupRoad => 'Connect your village',
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

  String get _hint => widget.observing
      ? widget.waitingMessage ??
            'Watch the public board while private hands stay hidden'
      : s.tactical != null
      ? 'Resolve this response to continue the turn'
      : switch (s.phase) {
          MatchPhase.setupVillage =>
            'Tap a glowing junction · first placements are free',
          MatchPhase.setupRoad => 'Tap a glowing edge beside your new village',
          MatchPhase.roll => 'Roll the dice to collect this turn’s production',
          MatchPhase.bandit => 'Tap another hex, then choose a neighbour',
          MatchPhase.invasion => 'Review the fleet and your shared defence',
          MatchPhase.finished => '15 Victory Points · a realm to remember',
          MatchPhase.actions => switch (move) {
            _Move.road =>
              '${_costLabel(MatchEngine.effectiveRoadCost(s))} · tap a glowing edge',
            _Move.village =>
              '${_costLabel(MatchEngine.villageCost)} · tap a glowing junction',
            _Move.inspect =>
              'Build, trade or play a card · pinch to zoom the map',
            _ => 'Tap a glowing target on the map',
          },
        };

  @override
  Widget build(BuildContext context) {
    final phase = s.phase;
    return Material(
      color: const Color(0xff101e25),
      child: SafeArea(
        child: Column(
          children: [
            _playerBar(),
            InvasionFeedback(state: s),
            Expanded(
              child: LayoutBuilder(
                builder: (context, bounds) {
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
                              if (s.tactical == null && !widget.observing)
                                Row(
                                  children: [
                                    Expanded(child: _tabs()),
                                    if (!desktop)
                                      IconButton(
                                        tooltip: _panelExpanded
                                            ? 'Narrow action panel'
                                            : 'Expand action panel',
                                        onPressed: () => setState(() {
                                          _panelExpanded = !_panelExpanded;
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
                                child: widget.observing
                                    ? SingleChildScrollView(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          children: [
                                            Icon(
                                              widget.online
                                                  ? Icons.sync
                                                  : Icons.smart_toy_outlined,
                                              size: 36,
                                              color: Color(0xffe5c183),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              widget.automationError == null
                                                  ? widget.online
                                                        ? 'Waiting for players'
                                                        : 'Computer turn'
                                                  : 'Computer paused',
                                              style: const TextStyle(
                                                fontSize: 20,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              s
                                                  .players[s
                                                          .tactical
                                                          ?.responder ??
                                                      s.active]
                                                  .id,
                                            ),
                                            const SizedBox(height: 16),
                                            if (widget.automationError == null)
                                              const LinearProgressIndicator()
                                            else ...[
                                              Text(widget.automationError!),
                                              FilledButton(
                                                onPressed:
                                                    widget.onResumeAutomation,
                                                child: const Text(
                                                  'Resume computer',
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 12),
                                            Text(
                                              widget.waitingMessage ?? 'Watch the realm grow. Your turn will open automatically.',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : s.tactical != null
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
                                          children: _panelContents(phase),
                                        ),
                                      ),
                              ),
                              if (s.tactical == null && !widget.observing)
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
            if (widget.online || (s.tactical == null && !widget.observing))
              _resourceTray()
            else
              const SizedBox(
                height: 48,
                child: Center(child: Text('Private hands are concealed')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _playerBar() => LayoutBuilder(
    builder: (context, bounds) {
      final winner = MatchEngine.winner(s);
      final height = math.max(
        _compact ? 48.0 : 52.0,
        MediaQuery.textScalerOf(context).scale(12) * 1.2 +
            MediaQuery.textScalerOf(context).scale(10) * 1.2 +
            24,
      );
      final width = math.max(
        128.0 * MediaQuery.textScalerOf(context).scale(12) / 12,
        (bounds.maxWidth - 50) / s.players.length - 6,
      );
      return Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(8, 5, 42, 5),
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
                      vertical: 4,
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
                                    ? 'Taking a turn'
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

  Widget _map() => Stack(
    children: [
      Positioned.fill(
        child: LayoutBuilder(
          builder: (context, box) {
            // Keep the instruction strip outside the interactive map coordinates.
            final size = Size(
              box.maxWidth,
              math.max(1, box.maxHeight - _instructionHeight),
            );
            _boardSize = size;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: ClipRect(
                  child: InteractiveViewer(
                    transformationController: _camera,
                    minScale: 1,
                    maxScale: 3.5,
                    boundaryMargin: const EdgeInsets.all(80),
                    child: Semantics(
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
                          ),
                          child: const SizedBox.expand(),
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
      Positioned(
        top: 8,
        left: 10,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xe614242b),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'ROUND ${s.round}\nFleet ${s.reaverPressure}/3 · Defence ${MatchEngine.defenceStrength(s) + s.invasionAid}',
              style: const TextStyle(
                color: Color(0xffc4d2cf),
                fontSize: 10,
                letterSpacing: .6,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        right: 6,
        top: 0,
        child: IconButton(
          tooltip: 'Reset map zoom',
          onPressed: () => _camera.value = Matrix4.identity(),
          icon: const Icon(Icons.center_focus_strong, size: 20),
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
              onTap: () => setState(() {
                _tab = index;
                if (index != 0) {
                  choice = _Move.inspect;
                  selectedKnight = null;
                }
              }),
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
                Text(cost, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          if (choice == action)
            const Icon(Icons.check_circle_outline, size: 20),
        ],
      ),
    ),
  );

  List<Widget> _panelContents(MatchPhase phase) {
    if (_tab == 0) {
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
            phase == MatchPhase.setupVillage ? 'Village · free' : 'Road · free',
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
                'Village → Town → Capital',
                MatchEngine.legalUpgrades(s).isNotEmpty,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            key: PageStorageKey('knights-${s.active}'),
            title: const Text('Knights & defence'),
            subtitle: _compact
                ? null
                : const Text('Fortify, recruit and move Knights'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in <(_Move, String, bool)>[
                    (
                      _Move.fortify,
                      'Fortify',
                      s.sites.keys.any((v) => MatchEngine.legalFort(s, v)),
                    ),
                    (
                      _Move.recruit,
                      'Recruit Knight',
                      [
                        for (var v = 0; v < s.topology.vertices.length; v++)
                          if (MatchEngine.legalRecruit(s, v)) v,
                      ].isNotEmpty,
                    ),
                    (
                      _Move.activate,
                      'Activate',
                      s.knights.keys.any(
                        (v) => MatchEngine.legalActivate(s, v),
                      ),
                    ),
                    (
                      _Move.promote,
                      'Promote',
                      s.knights.keys.any((v) => MatchEngine.legalPromote(s, v)),
                    ),
                    (
                      _Move.knightMove,
                      'Move Knight',
                      s.knights.keys.any(
                        (v) =>
                            s.knights[v]!.owner == s.active &&
                            MatchEngine.legalKnightDestinations(
                              s,
                              v,
                            ).isNotEmpty,
                      ),
                    ),
                  ])
                    ChoiceChip(
                      label: Text(entry.$2),
                      selected: choice == entry.$1,
                      onSelected: entry.$3
                          ? (_) => setState(() {
                              choice = entry.$1;
                              selectedKnight = null;
                            })
                          : null,
                    ),
                ],
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
                  Text(
                    'Fleet strength ${MatchEngine.invasionStrength(s)} · Defence ${MatchEngine.defenceStrength(s) + s.invasionAid}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
    if (_tab == 1) {
      final result = latestTradeFeedback(s);
      return [
        if (result != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(result, key: const ValueKey('trade-result')),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: phase == MatchPhase.actions ? exchange : null,
          icon: const Icon(Icons.account_balance_outlined),
          label: const Text('Bank trade'),
        ),
        SizedBox(height: _compact ? 4 : 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: phase == MatchPhase.actions ? offer : null,
          icon: const Icon(Icons.handshake_outlined),
          label: const Text('Player trade'),
        ),
        if (phase != MatchPhase.actions)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Trading opens after your roll and any pending events.',
            ),
          ),
        if (phase == MatchPhase.actions && s.offers.isNotEmpty)
          for (final trade in s.offers)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Offer #' +
                          trade.id.toString() +
                          ': ' +
                          s.players[trade.proposer].id +
                          ' gives ' +
                          trade.giveCount.toString() +
                          ' ' +
                          trade.give.name +
                          ' for ' +
                          trade.wantCount.toString() +
                          ' ' +
                          trade.want.name +
                          ' from ' +
                          s.players[trade.target].id,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (trade.target == s.active) ...[
                      const Text(
                        'Decide this turn; escrow is held until expiry.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => send(
                              RespondTrade(s.active, false, offerId: trade.id),
                            ),
                            child: const Text('Decline'),
                          ),
                          FilledButton(
                            onPressed:
                                (s.current.stores[trade.want] ?? 0) >=
                                    trade.wantCount
                                ? () => send(
                                    RespondTrade(
                                      s.active,
                                      true,
                                      offerId: trade.id,
                                    ),
                                  )
                                : null,
                            child: const Text('Accept'),
                          ),
                          if (!trade.isCounter &&
                              s.offers.every((o) => o.proposer != s.active))
                            TextButton(
                              onPressed: () => offer(trade),
                              child: const Text('Counter'),
                            ),
                        ],
                      ),
                    ] else if (trade.proposer == s.active) ...[
                      const Text(
                        'Waiting for their action turn. Your goods are reserved until accepted, declined, or expired.',
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => send(WithdrawTrade(trade.id)),
                          child: const Text('Withdraw'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

        if (s.offers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text(
              'No standing offers',
              style: TextStyle(color: Color(0xffabbfc2)),
            ),
          ),
      ];
    }
    if (_tab == 2) {
      if (phase != MatchPhase.actions) {
        return [
          _heading(
            'Strategy cards',
            'Roll and resolve pending events before playing cards.',
          ),
        ];
      }
      return [
        StrategyHand(
          state: s,
          onEvent: send,
          onlineOptions: widget.online
              ? (widget.onlineView?['options'] as Map?)
              : null,
        ),
      ];
    }
    return [
      _heading('Your realm', 'Develop your towns and follow the race to 15.'),
      ExpansionTile(
        key: PageStorageKey('developments-${s.active}'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Town Developments'),
        subtitle: const Text(
          'Innovation, Commerce & Governance',
          style: TextStyle(fontSize: 11),
        ),
        children: [
          for (final track in StrategyDeck.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${track.name} · ${s.current.level(track)}/5',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        s.current.level(track) < 5
                            ? 'Next: ${track.tiers[s.current.level(track)]}'
                            : 'Complete',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (s.current.level(track) < 5)
                        Text(
                          _costLabel(
                            MatchEngine.developmentCost(
                              s,
                              track,
                              s.current.level(track) + 1,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xffabbfc2),
                          ),
                        ),
                      const SizedBox(height: 6),
                      OutlinedButton(
                        onPressed: MatchEngine.canDevelop(s, track)
                            ? () => send(DevelopTown(track))
                            : null,
                        child: Text(
                          s.current.level(track) == 5 ? 'Max' : 'Develop',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Reaver Fleet ${s.reaverPressure}/3 · Defence ${MatchEngine.defenceStrength(s) + s.invasionAid}',
      ),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Replay copied')),
                  );
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
                  const SnackBar(
                    content: Text(
                      'Share code copied; it contains every private hand.',
                    ),
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
            if (s.longestRoadHolder == i) const Icon(Icons.military_tech),
          ],
        ),
      if (s.dice != null)
        Text(
          widget.online
              ? 'Last dice: ${s.dice} · Event ${widget.onlineView?['eventCount']}'
              : 'Last dice: ${s.dice} · Event ${s.events.length}',
        ),
    ];
  }

  Widget _turnAction() => Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: _compact ? 2 : 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xff34464a))),
    ),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: const Color(0xffe5c183),
          foregroundColor: const Color(0xff28271e),
        ),
        onPressed: switch (s.phase) {
          MatchPhase.roll => () async {
            final before = s;
            final pair = widget.online ? (0, 0) : MatchEngine.expectedDice(s);
            if (!MediaQuery.disableAnimationsOf(context)) {
              await showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => DiceRoll(first: pair.$1, second: pair.$2),
              );
            }
            if (!mounted || !identical(s, before)) return;
            send(RollDice(pair.$1, pair.$2));
          },
          MatchPhase.actions => () => send(const EndTurn()),
          MatchPhase.invasion => () => send(const ResolveInvasion()),
          _ => null,
        },
        icon: Icon(
          s.phase == MatchPhase.roll
              ? Icons.casino_outlined
              : s.phase == MatchPhase.invasion
              ? Icons.shield_outlined
              : Icons.check_circle_outline,
        ),
        label: Text(
          s.phase == MatchPhase.roll
              ? 'Roll dice'
              : s.phase == MatchPhase.invasion
              ? 'Resolve Invasion'
              : s.phase == MatchPhase.actions
              ? 'End turn'
              : s.phase == MatchPhase.finished
              ? 'Match complete'
              : 'Place on map',
        ),
      ),
    ),
  );

  Widget _resourceTray() => Container(
    height: math.max(
      _compact ? 44 : 58,
      MediaQuery.textScalerOf(context).scale(_compact ? 14 : 17) * 1.2 +
          MediaQuery.textScalerOf(context).scale(_compact ? 9 : 10) * 1.2 +
          (_compact ? 13 : 17),
    ),
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: _compact ? 4 : 6),
    decoration: const BoxDecoration(
      color: Color(0xff101e25),
      border: Border(top: BorderSide(color: Color(0xff34464a))),
    ),
    child: Row(
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(
            Icons.inventory_2_outlined,
            size: 20,
            color: Color(0xffe5c183),
          ),
        ),
        for (final r in Resource.values)
          Expanded(
            child: Tooltip(
              message: '${r.name}: ${inventoryOwner.stores[r] ?? 0}',
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${inventoryOwner.stores[r] ?? 0}',
                      style: TextStyle(
                        fontSize: _compact ? 14 : 17,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _compact ? 9 : 10,
                        height: 1.2,
                        color: Color(0xffbac9cc),
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
  const _TradeComposer({required this.state, required this.kind, this.counter});
  final MatchState state;
  final _TradeKind kind;
  final TradeProposal? counter;

  @override
  State<_TradeComposer> createState() => _TradeComposerState();
}

class _TradeComposerState extends State<_TradeComposer> {
  late int target;
  late Resource give;
  late Resource take;
  late int giveCount;
  late int takeCount;

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
      final rate = widget.kind == _TradeKind.bank
          ? MatchEngine.tradeRate(s, s.active)
          : 1;
      final payable = Resource.values.where(
        (good) => (s.current.stores[good] ?? 0) >= rate,
      );
      if (payable.isNotEmpty) give = payable.first;
      if (give == take) {
        take = Resource.values.firstWhere((good) => good != give);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final bank = widget.kind == _TradeKind.bank;
    final rate = MatchEngine.tradeRate(s, s.active);
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
        toolbarHeight: 48,
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
          Text(
            bank
                ? 'Rate $rate:$receipt · Bank stock: $bankAvailable'
                : 'Only ${s.players[target].id} can accept. Private hands stay hidden.',
            style: const TextStyle(fontSize: 12, color: Color(0xffabbfc2)),
          ),
          const SizedBox(height: 12),
          if (!bank && widget.counter == null) ...[
            DropdownButtonFormField<int>(
              key: ValueKey(target),
              initialValue: target,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Offer to',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (var i = 0; i < s.players.length; i++)
                  if (i != s.active)
                    DropdownMenuItem(value: i, child: Text(s.players[i].id)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => target = v);
              },
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Give $required',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _GoodInput(
                      label: bank ? 'Pay' : 'Place in escrow',
                      resource: give,
                      change: (v) => setState(() => give = v),
                    ),
                    if (!bank)
                      _CountInput(
                        value: giveCount,
                        change: (v) => setState(() => giveCount = v),
                      ),
                    Text(
                      'Available: $available · Required: $required',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 36, 12, 0),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xffe5c183),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Receive ${bank ? receipt : takeCount}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _GoodInput(
                      label: bank ? 'From bank' : 'Request',
                      resource: take,
                      change: (v) => setState(() => take = v),
                    ),
                    if (!bank)
                      _CountInput(
                        value: takeCount,
                        change: (v) => setState(() => takeCount = v),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
        minimum: const EdgeInsets.all(16),
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
                      ? 'Escrow and offer'
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
        if (w.kind == TacticalKind.invasion)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Expected outcome without more aid'),
            children: [Text(MatchEngine.invasionForecast(state))],
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
        Text(detail, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
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

class _GoodInput extends StatelessWidget {
  const _GoodInput({
    required this.label,
    required this.resource,
    required this.change,
  });
  final String label;
  final Resource resource;
  final ValueChanged<Resource> change;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<Resource>(
    key: ValueKey(label + resource.name),
    initialValue: resource,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final r in Resource.values)
        DropdownMenuItem(value: r, child: Text(r.name)),
    ],
    onChanged: (r) {
      if (r != null) change(r);
    },
  );
}

class _CountInput extends StatelessWidget {
  const _CountInput({required this.value, required this.change});
  final int value;
  final ValueChanged<int> change;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text('Quantity: $value')),
      IconButton(
        onPressed: value > 1 ? () => change(value - 1) : null,
        icon: const Icon(Icons.remove_circle_outline),
        tooltip: 'Decrease',
      ),
      IconButton(
        onPressed: value < 8 ? () => change(value + 1) : null,
        icon: const Icon(Icons.add_circle_outline),
        tooltip: 'Increase',
      ),
    ],
  );
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
  const _Painter(this.state, this.mode, this.selectedKnight);
  final MatchState state;
  final _Move mode;
  final int? selectedKnight;

  @override
  void paint(Canvas canvas, Size size) {
    final g = BoardGeometry(size);
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xff31545c), Color(0xff152e38), Color(0xff10242e)],
          radius: .8,
        ).createShader(bounds),
    );
    for (var ring = 0; ring < 5; ring++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: g.center,
          width: g.radius * (8.3 + ring * .75) * BoardGeometry.horizontalScale,
          height: g.radius * (7.7 + ring * .75) * BoardGeometry.verticalScale,
        ),
        Paint()
          ..color = const Color(0xffa4c2bd).withValues(alpha: .055)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
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
      canvas.scale(BoardGeometry.horizontalScale, BoardGeometry.verticalScale);
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
        canvas.drawShadow(
          Path()..addOval(Rect.fromCircle(center: c, radius: radius * .35)),
          Colors.black,
          radius * .06,
          true,
        );
        canvas.drawCircle(
          c,
          radius * .35,
          Paint()..color = const Color(0xfff5e6c4),
        );
        canvas.drawCircle(
          c,
          radius * .30,
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
          radius * .46,
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
    for (final e in state.topology.edges) {
      final owner = state.roads[e.id];
      if (owner == null && !legalRoads.contains(e.id)) continue;
      final a = g.vertex(state.topology.vertices[e.a]);
      final b = g.vertex(state.topology.vertices[e.b]);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xff1b2834)
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = owner == null ? const Color(0xffafffe3) : seatColors[owner]
          ..strokeWidth = owner == null ? 5 : 6
          ..strokeCap = StrokeCap.round,
      );
    }
    final legal = switch (mode) {
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
    for (final v in state.topology.vertices) {
      final c = g.vertex(v);
      if (legal.contains(v.id)) {
        canvas.drawCircle(
          c,
          math.max(7, g.radius * .22),
          Paint()..color = const Color(0xffaeffdf).withValues(alpha: .45),
        );
        canvas.drawCircle(
          c,
          math.max(3.5, g.radius * .10),
          Paint()..color = const Color(0xfff6fff0),
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
    final ink = Paint()
      ..color = const Color(0xff172f31).withValues(alpha: .28)
      ..strokeWidth = r * .025
      ..strokeCap = StrokeCap.round;
    final light = Paint()
      ..color = const Color(0xfff6e8b4).withValues(alpha: .21)
      ..strokeWidth = r * .025
      ..style = PaintingStyle.stroke;
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 4; col++) {
        final x = c.dx + (col - 1.5) * r * .43 + (row.isEven ? .12 : -.12) * r;
        final y = c.dy + (row - 1) * r * .49;
        final p = Offset(x, y);
        switch (land) {
          case Land.woodland:
            canvas.drawLine(
              p + Offset(0, r * .04),
              p + Offset(0, r * .27),
              ink,
            );
            final tree = Path()
              ..moveTo(x, y - r * .24)
              ..lineTo(x - r * .16, y + r * .12)
              ..lineTo(x + r * .16, y + r * .12)
              ..close();
            canvas.drawPath(
              tree,
              Paint()..color = const Color(0xff1c4c3b).withValues(alpha: .5),
            );
            canvas.drawLine(
              p + Offset(0, -r * .19),
              p + Offset(-r * .1, r * .07),
              light,
            );
          case Land.ridges:
            final mountain = Path()
              ..moveTo(x - r * .25, y + r * .20)
              ..lineTo(x, y - r * .26)
              ..lineTo(x + r * .24, y + r * .20)
              ..close();
            canvas.drawPath(mountain, ink);
            canvas.drawPath(
              Path()
                ..moveTo(x - r * .09, y - r * .08)
                ..lineTo(x, y - r * .26)
                ..lineTo(x + r * .08, y - r * .1),
              light,
            );
          case Land.fields:
            for (var line = 0; line < 3; line++) {
              final yy = y + line * r * .065;
              canvas.drawLine(
                Offset(x - r * .17, yy),
                Offset(x + r * .17, yy - r * .13),
                light,
              );
            }
            canvas.drawLine(
              p + Offset(0, -r * .14),
              p + Offset(0, r * .12),
              ink,
            );
          case Land.clayBeds:
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: p, width: r * .33, height: r * .15),
                Radius.circular(r * .03),
              ),
              ink,
            );
            canvas.drawLine(
              p + Offset(-r * .12, -r * .04),
              p + Offset(r * .12, -r * .04),
              light,
            );
          case Land.meadows:
            final hill = Path()
              ..moveTo(x - r * .22, y + r * .1)
              ..quadraticBezierTo(x, y - r * .2, x + r * .22, y + r * .1);
            canvas.drawPath(hill, light);
            canvas.drawLine(
              p + Offset(-r * .08, r * .16),
              p + Offset(-r * .04, r * .04),
              ink,
            );
          case Land.barren:
            final dune = Path()
              ..moveTo(x - r * .22, y)
              ..quadraticBezierTo(x, y - r * .12, x + r * .23, y + r * .04);
            canvas.drawPath(dune, light);
        }
      }
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
      old.selectedKnight != selectedKnight;
}
