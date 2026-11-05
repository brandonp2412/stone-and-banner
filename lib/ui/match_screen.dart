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
    this.online = false,
    this.onlineView,
  });
  final MatchState state;
  final ValueChanged<MatchEvent> onEvent;
  final bool online;
  final Map<String, dynamic>? onlineView;
  @override
  State<MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<MatchView> {
  _Move choice = _Move.inspect;
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant MatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.phase != widget.state.phase ||
        oldWidget.state.active != widget.state.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int? selectedKnight;
  Size? _boardSize;
  MatchState get s => widget.state;
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
    final g = _Geometry(size);
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
            '${selected.land.name} · Number ${selected.productionNumber?.toString() ?? '—'}',
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
              '${s.board.tiles[t].land.name} ${s.board.tiles[t].productionNumber ?? 'unnumbered'}',
        )
        .join(', ');
    if (move == _Move.bandit) {
      final tile = s.board.tiles[id];
      return 'Hex ${id + 1}: ${tile.land.name}, ${tile.productionNumber ?? 'no number'}';
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
    final geometry = _Geometry(boardSize);
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
    final event = await Navigator.of(context).push<MatchEvent>(
      MaterialPageRoute(
        builder: (_) => _TradeComposer(state: s, kind: kind, counter: counter),
      ),
    );
    if (mounted && event != null) send(event);
  }

  @override
  Widget build(BuildContext context) {
    if (s.tactical != null) {
      return _TacticalPanel(state: s, onEvent: send, online: widget.online);
    }
    final phase = s.phase;
    final winner = MatchEngine.winner(s);
    final instruction = switch (phase) {
      MatchPhase.setupVillage => 'Tap a glowing junction for a free Village',
      MatchPhase.setupRoad => 'Tap a glowing side for your free Road',
      MatchPhase.roll => 'Roll two dice to gather goods',
      MatchPhase.bandit => 'Tap a new hex to move the Bandit',
      MatchPhase.finished => 'Victory!',
      MatchPhase.invasion =>
        'Reaver Fleet Invasion · review defence and resolve the outcome',
      MatchPhase.actions => switch (move) {
        _Move.village => 'Tap a glowing junction · wood + brick + wheat + wool',
        _Move.road => 'Tap a glowing road · wood + brick',
        _Move.upgrade => 'Tap your glowing Village or Town to upgrade',
        _Move.fortify => 'Tap a glowing Town to raise Fortifications',
        _Move.recruit => 'Tap an open road junction to recruit a Sentinel',
        _Move.activate => 'Tap your inactive Knight to activate',
        _Move.promote => 'Tap an active Knight to promote',
        _Move.knightMove =>
          selectedKnight == null
              ? 'Select your active Knight'
              : 'Tap a glowing destination',
        _ => 'Pinch to zoom · drag to pan · tap to inspect',
      },
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Round ${s.round} · ${phase.name}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        winner == null
                            ? s.current.id
                            : '${s.players[winner].id} wins!',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      '${MatchEngine.score(s, winner ?? s.active)} / 15 VP',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            if (phase == MatchPhase.roll)
              Card.filled(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ready to roll',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () {
                          final pair = widget.online
                              ? (0, 0)
                              : MatchEngine.expectedDice(s);
                          send(RollDice(pair.$1, pair.$2));
                        },
                        icon: const Icon(Icons.casino),
                        label: const Text('Roll dice'),
                      ),
                    ],
                  ),
                ),
              ),
            if (phase == MatchPhase.invasion)
              Card.filled(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Defend against the Reaver Fleet',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fleet strength ${MatchEngine.invasionStrength(s)} · Defence ${MatchEngine.defenceStrength(s) + s.invasionAid}',
                      ),
                      if (s.invasionAid > 0)
                        Text('Emergency aid +${s.invasionAid} included'),
                      const Text(
                        'Active Knights and Fortifications defend. A failed defence can damage a Town or Capital.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => send(const ResolveInvasion()),
                        icon: const Icon(Icons.shield_outlined),
                        label: const Text('Resolve Invasion'),
                      ),
                    ],
                  ),
                ),
              ),
            if (phase == MatchPhase.actions)
              Card.filled(
                key: const ValueKey('mobile-action-panel'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Your next move',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        choice == _Move.inspect
                            ? 'Choose a legal build, trade, or finish your turn.'
                            : instruction,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Inspect'),
                            selected: choice == _Move.inspect,
                            onSelected: (_) =>
                                setState(() => choice = _Move.inspect),
                          ),
                          if (MatchEngine.legalEdges(s).isNotEmpty)
                            ChoiceChip(
                              label: const Text('Build road'),
                              selected: choice == _Move.road,
                              onSelected: (_) =>
                                  setState(() => choice = _Move.road),
                            ),
                          if (MatchEngine.legalVertices(s).isNotEmpty)
                            ChoiceChip(
                              label: const Text('Build village'),
                              selected: choice == _Move.village,
                              onSelected: (_) =>
                                  setState(() => choice = _Move.village),
                            ),
                          if (MatchEngine.legalUpgrades(s).isNotEmpty)
                            ChoiceChip(
                              label: const Text('Upgrade site'),
                              selected: choice == _Move.upgrade,
                              onSelected: (_) =>
                                  setState(() => choice = _Move.upgrade),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => send(const EndTurn()),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('End turn'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: exchange,
                            icon: const Icon(Icons.currency_exchange),
                            label: const Text('Bank trade'),
                          ),
                          OutlinedButton.icon(
                            onPressed: offer,
                            icon: const Icon(Icons.handshake_outlined),
                            label: const Text('Player trade'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Strategy cards, Knights and Town Developments are below the board.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    Text(
                      instruction,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    AspectRatio(
                      aspectRatio: 1.1,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final size = Size(box.maxWidth, box.maxHeight);
                          _boardSize = size;
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: InteractiveViewer(
                              minScale: .8,
                              maxScale: 3.5,
                              boundaryMargin: const EdgeInsets.all(100),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (details) =>
                                    tapBoard(details.localPosition, size),
                                child: CustomPaint(
                                  painter: _Painter(s, move, selectedKnight),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (availableTargets.isNotEmpty) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: chooseTarget,
                icon: const Icon(Icons.format_list_numbered),
                label: const Text('Choose board target from list'),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 1,
              children: [
                for (final r in Resource.values)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${r.name} ${s.current.stores[r] ?? 0}'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Reaver Fleet ${s.reaverPressure}/3 · Defence ${MatchEngine.defenceStrength(s) + s.invasionAid} · First Capital: ${s.firstCapitalOwner == null ? 'unclaimed' : s.players[s.firstCapitalOwner!].id}',
            ),
            if (s.lastInvasion.isNotEmpty) Text(s.lastInvasion),
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
                                  RespondTrade(
                                    s.active,
                                    false,
                                    offerId: trade.id,
                                  ),
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
                            'Your goods are reserved until accepted, declined, or expired.',
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
            if (phase == MatchPhase.actions) ...[
              ExpansionTile(
                title: const Text('Knights & defence'),
                subtitle: const Text('Fortify, recruit and move Knights'),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  Wrap(
                    spacing: 8,
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
                          s.knights.keys.any(
                            (v) => MatchEngine.legalPromote(s, v),
                          ),
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
                        if (entry.$3)
                          ChoiceChip(
                            label: Text(entry.$2),
                            selected: choice == entry.$1,
                            onSelected: (_) => setState(() {
                              choice = entry.$1;
                              selectedKnight = null;
                            }),
                          ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              StrategyHand(
                state: s,
                onEvent: send,
                onlineOptions: widget.online
                    ? (widget.onlineView?["options"] as Map?)
                    : null,
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                title: const Text('Town Developments'),
                subtitle: const Text('Innovation, Commerce & Governance'),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final track in StrategyDeck.values)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${track.name} · ${s.current.level(track)}/5'
                                      '${s.current.level(track) < 5 ? " · Next: ${track.tiers[s.current.level(track)]}" : " · Complete"}',
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: MatchEngine.canDevelop(s, track)
                                        ? () => send(DevelopTown(track))
                                        : null,
                                    child: Text(
                                      s.current.level(track) == 5
                                          ? 'Max'
                                          : 'Develop',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Standings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!widget.online)
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: MatchEngine.exportReplay(s)),
                      );
                      if (context.mounted) {
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
                    if (context.mounted) {
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
          ],
        ),
      ),
    );
  }
}

enum _TradeKind { bank, player }

/// A dedicated route keeps negotiation away from crowded board actions.
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
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Text(
                  bank ? 'Trade with the bank at your current rate.' : 'Set the terms. Your goods are reserved in escrow until resolution.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                if (!bank && widget.counter == null) ...[
                  DropdownButtonFormField<int>(
                    key: ValueKey(target),
                    initialValue: target,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Offer to',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var i = 0; i < s.players.length; i++)
                        if (i != s.active)
                          DropdownMenuItem(
                            value: i,
                            child: Text(s.players[i].id),
                          ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => target = v);
                    },
                  ),
                  const SizedBox(height: 20),
                ],
                Text('Give', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
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
                  'Available: ' +
                      available.toString() +
                      ' · Required: ' +
                      required.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Text('Receive', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
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
                if (bank)
                  Text(
                    'Rate ' +
                        rate.toString() +
                        ':' +
                        receipt.toString() +
                        ' · Bank stock: ' +
                        bankAvailable.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 24),
                Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      bank
                          ? 'Pay ' +
                                rate.toString() +
                                ' ' +
                                give.name +
                                ' · Receive ' +
                                receipt.toString() +
                                ' ' +
                                take.name
                          : 'Reserve ' +
                                giveCount.toString() +
                                ' ' +
                                give.name +
                                ' · Request ' +
                                takeCount.toString() +
                                ' ' +
                                take.name +
                                '\nOnly ' +
                                s.players[target].id +
                                ' can accept. Private hands stay hidden.',
                    ),
                  ),
                ),
                if (!valid) ...[
                  const SizedBox(height: 8),
                  Text(
                    give == take
                        ? 'Choose different goods.'
                        : available < required
                        ? 'Insufficient goods to offer.'
                        : bank && bankAvailable < receipt
                        ? 'Bank stock is too low.'
                        : 'Check the trade terms.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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

/// The entire normal hand/board is hidden for a visiting reaction seat.
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Response for ' + state.players[responder].id,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 420,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 170),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Card(
                  key: ValueKey(w.id.toString() + ':' + responder.toString()),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 10),
                                Text(detail),
                                const SizedBox(height: 12),
                                Text(
                                  'Response allowance: ' +
                                      (state.reactionsUsed.contains(responder)
                                          ? 'spent'
                                          : 'available'),
                                ),
                                if (w.kind == TacticalKind.bandit &&
                                    MatchEngine.canIntercept(state, responder))
                                  FilledButton.icon(
                                    onPressed: () => onEvent(
                                      RespondTactical(
                                        w.id,
                                        responder,
                                        TacticalChoice.intercept,
                                      ),
                                    ),
                                    icon: const Icon(Icons.shield_outlined),
                                    label: const Text('Intercept with Knight'),
                                  ),
                                if (w.kind == TacticalKind.governance)
                                  for (final i in MatchEngine.counterCards(
                                    state,
                                    responder,
                                    w.card!,
                                  ))
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
                                        'Counter: ' +
                                            state
                                                .players[responder]
                                                .cards[i]
                                                .definition
                                                .name,
                                      ),
                                    ),
                                if (w.kind == TacticalKind.invasion)
                                  for (final good in [
                                    Resource.wheat,
                                    Resource.ore,
                                  ])
                                    if ((state
                                                .players[responder]
                                                .stores[good] ??
                                            0) >
                                        0)
                                      FilledButton.icon(
                                        onPressed: () => onEvent(
                                          RespondTactical(
                                            w.id,
                                            responder,
                                            TacticalChoice.aid,
                                            good: good,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.volunteer_activism_outlined,
                                        ),
                                        label: Text('Pledge 1 ' + good.name),
                                      ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton(
                          onPressed: () => onEvent(
                            RespondTactical(
                              w.id,
                              responder,
                              TacticalChoice.pass,
                            ),
                          ),
                          child: const Text('Pass'),
                        ),
                        if (!online)
                          TextButton(
                            onPressed: () =>
                                onEvent(TimeoutTactical(w.id, responder)),
                            child: const Text('Skip / timeout fallback'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only this seat’s reaction choices are shown. '
              'A response or pass returns play to the original turn.',
            ),
          ],
        ),
      ),
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

class _Geometry {
  _Geometry(this.size);
  final Size size;
  double get radius => math.min(size.width / 9.8, size.height / 9.3);
  Offset get center => Offset(size.width / 2, size.height / 2);
  Offset vertex(BoardVertex p) => center + Offset(p.x * radius, p.y * radius);
  Offset tile(HexCoord p) =>
      center +
      Offset(math.sqrt(3) * radius * (p.q + p.r / 2), 1.5 * radius * p.r);
}

class _Painter extends CustomPainter {
  const _Painter(this.state, this.mode, this.selectedKnight);
  final MatchState state;
  final _Move mode;
  final int? selectedKnight;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(size);
    canvas.drawColor(const Color(0xff1c343d), BlendMode.src);
    for (var i = 0; i < state.board.tiles.length; i++) {
      final tile = state.board.tiles[i];
      final c = g.tile(tile.position), radius = g.radius;
      final hex = Path();
      for (var n = 0; n < 6; n++) {
        final angle = (n * 60 - 30) * math.pi / 180;
        final p =
            c + Offset(radius * math.cos(angle), radius * math.sin(angle));
        if (n == 0) {
          hex.moveTo(p.dx, p.dy);
        } else {
          hex.lineTo(p.dx, p.dy);
        }
      }
      hex.close();
      canvas.drawPath(hex, Paint()..color = landColors[tile.land.index]);
      canvas.drawPath(
        hex,
        Paint()
          ..color = const Color(0xff213944)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      // Each hex gets a small native motif, without third-party tiles or art.
      final motif = Paint()
        ..color = Colors.white.withValues(alpha: .25)
        ..strokeWidth = 1.7
        ..style = PaintingStyle.stroke;
      if (tile.land == Land.woodland) {
        for (final dx in [-.45, .45]) {
          final x = c.dx + dx * radius, y = c.dy - radius * .5;
          canvas.drawLine(Offset(x, y), Offset(x, y + radius * .32), motif);
          canvas.drawLine(
            Offset(x, y),
            Offset(x - radius * .15, y + radius * .2),
            motif,
          );
          canvas.drawLine(
            Offset(x, y),
            Offset(x + radius * .15, y + radius * .2),
            motif,
          );
        }
      } else if (tile.land == Land.ridges) {
        final p = Path()
          ..moveTo(c.dx - radius * .6, c.dy - radius * .35)
          ..lineTo(c.dx - radius * .3, c.dy - radius * .65)
          ..lineTo(c.dx, c.dy - radius * .34)
          ..lineTo(c.dx + radius * .3, c.dy - radius * .62)
          ..lineTo(c.dx + radius * .6, c.dy - radius * .34);
        canvas.drawPath(p, motif);
      } else {
        for (final dx in [-.5, .38]) {
          canvas.drawLine(
            c + Offset(dx * radius, -radius * .5),
            c + Offset((dx + .18) * radius, -radius * .37),
            motif,
          );
        }
      }
      if (tile.productionNumber case final int number) {
        canvas.drawCircle(
          c,
          radius * .32,
          Paint()..color = const Color(0xfffbefda),
        );
        _label(
          canvas,
          '$number',
          c,
          radius * .3,
          number == 6 || number == 8
              ? const Color(0xffab332f)
              : const Color(0xff23373c),
        );
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
          math.max(11, g.radius * .29),
          Paint()..color = const Color(0xffaeffdf).withValues(alpha: .45),
        );
        canvas.drawCircle(c, 6.5, Paint()..color = const Color(0xfff6fff0));
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
