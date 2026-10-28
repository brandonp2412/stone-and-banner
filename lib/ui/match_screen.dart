import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/advanced.dart';
import '../engine/board.dart';
import '../engine/game.dart';
import '../engine/match.dart';
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
  const MatchView({super.key, required this.state, required this.onEvent});
  final MatchState state;
  final ValueChanged<MatchEvent> onEvent;
  @override
  State<MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<MatchView> {
  _Move choice = _Move.inspect;
  int? selectedKnight;
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

  void tapBoard(Offset tap, Size size) async {
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
      final victims = MatchEngine.banditVictims(s, best);
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

  Future<void> exchange() async {
    var give = Resource.wood, take = Resource.brick;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final rate = MatchEngine.tradeRate(s, s.active);
          final commerce = s.current.level(StrategyDeck.commerce);
          final receipt =
              commerce >= 5 || (commerce >= 3 && take == Resource.cloth)
              ? 2
              : 1;
          final valid =
              give != take &&
              (s.current.stores[give] ?? 0) >= rate &&
              (s.bank[take] ?? 0) >= receipt;
          return AlertDialog(
            title: Text('Bank trade · $rate:$receipt'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GoodInput(
                  label: 'Give $rate',
                  resource: give,
                  change: (r) => update(() => give = r),
                ),
                const SizedBox(height: 12),
                _GoodInput(
                  label: 'Receive $receipt',
                  resource: take,
                  change: (r) => update(() => take = r),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid
                    ? () {
                        Navigator.pop(context);
                        send(BankExchange(give, take));
                      }
                    : null,
                child: const Text('Exchange'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> offer() async {
    var target = (s.active + 1) % s.players.length;
    var give = Resource.wood, take = Resource.wool;
    var countGive = 1, countTake = 1;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final valid =
              give != take &&
              (s.current.stores[give] ?? 0) >= countGive &&
              (s.players[target].stores[take] ?? 0) >= countTake;
          return AlertDialog(
            title: const Text('Offer a trade'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    key: ValueKey(target),
                    initialValue: target,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Offer to'),
                    items: [
                      for (var i = 0; i < s.players.length; i++)
                        if (i != s.active)
                          DropdownMenuItem(
                            value: i,
                            child: Text(s.players[i].id),
                          ),
                    ],
                    onChanged: (v) => update(() => target = v!),
                  ),
                  const SizedBox(height: 12),
                  _GoodInput(
                    label: 'You give',
                    resource: give,
                    change: (r) => update(() => give = r),
                  ),
                  _CountInput(
                    value: countGive,
                    change: (n) => update(() => countGive = n),
                  ),
                  const SizedBox(height: 12),
                  _GoodInput(
                    label: 'You request',
                    resource: take,
                    change: (r) => update(() => take = r),
                  ),
                  _CountInput(
                    value: countTake,
                    change: (n) => update(() => countTake = n),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid
                    ? () {
                        Navigator.pop(context);
                        send(
                          ProposeTrade(
                            target,
                            give,
                            countGive,
                            take,
                            countTake,
                          ),
                        );
                      }
                    : null,
                child: const Text('Send offer'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              'Reaver Fleet ${s.reaverPressure}/3 · Defence ${MatchEngine.defenceStrength(s)} · First Capital: ${s.firstCapitalOwner == null ? 'unclaimed' : s.players[s.firstCapitalOwner!].id}',
            ),
            if (s.lastInvasion.isNotEmpty) Text(s.lastInvasion),
            if (s.trade case final TradeProposal trade)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${s.current.id} offers ${trade.giveCount} ${trade.give.name} for ${trade.wantCount} ${trade.want.name}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Decision: ${s.players[trade.target].id}'),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  send(RespondTrade(trade.target, false)),
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  send(RespondTrade(trade.target, true)),
                              child: const Text('Accept'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (phase == MatchPhase.invasion)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Fleet strength ${MatchEngine.invasionStrength(s)} · Defence ${MatchEngine.defenceStrength(s)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text(
                        'All active Knights and Fortifications defend. '
                        'A failed defence damages the highest-scoring Town '
                        'or Capital; a sole leading Knight defender may earn '
                        "Guardian's Honour.",
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => send(const ResolveInvasion()),
                        icon: const Icon(Icons.shield_outlined),
                        label: const Text('Resolve Invasion'),
                      ),
                    ],
                  ),
                ),
              )
            else if (phase == MatchPhase.roll)
              FilledButton.icon(
                onPressed: () {
                  final pair = MatchEngine.expectedDice(s);
                  send(RollDice(pair.$1, pair.$2));
                },
                icon: const Icon(Icons.casino),
                label: const Text('Roll dice'),
              )
            else if (phase == MatchPhase.actions) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('Inspect'),
                    selected: choice == _Move.inspect,
                    onSelected: (_) => setState(() => choice = _Move.inspect),
                  ),
                  ChoiceChip(
                    label: const Text('Road'),
                    selected: choice == _Move.road,
                    onSelected: MatchEngine.legalEdges(s).isNotEmpty
                        ? (_) => setState(() => choice = _Move.road)
                        : null,
                  ),
                  ChoiceChip(
                    label: const Text('Village'),
                    selected: choice == _Move.village,
                    onSelected: MatchEngine.legalVertices(s).isNotEmpty
                        ? (_) => setState(() => choice = _Move.village)
                        : null,
                  ),
                  ChoiceChip(
                    label: const Text('Upgrade'),
                    selected: choice == _Move.upgrade,
                    onSelected: MatchEngine.legalUpgrades(s).isNotEmpty
                        ? (_) => setState(() => choice = _Move.upgrade)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              StrategyHand(state: s, onEvent: send),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Town Developments',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: exchange,
                      child: const Text('Bank trade'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: offer,
                      child: const Text('Player trade'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => send(const EndTurn()),
                      child: const Text('End turn'),
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
              Text('Last dice: ${s.dice} · Event ${s.events.length}'),
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
