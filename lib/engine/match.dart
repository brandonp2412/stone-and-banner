import 'dart:convert';

import 'advanced.dart';
import 'board.dart';
import 'game.dart';

enum MatchPhase {
  setupVillage,
  setupRoad,
  roll,
  bandit,
  actions,
  invasion,
  finished,
}

class Site {
  const Site(this.owner, this.structure);
  final int owner;
  final Structure structure;
}

class TradeProposal {
  const TradeProposal(
    this.target,
    this.give,
    this.giveCount,
    this.want,
    this.wantCount,
  );
  final int target, giveCount, wantCount;
  final Resource give, want;
}

sealed class MatchEvent {
  const MatchEvent();
  Map<String, Object?> toJson();
}

class PlaceVillage extends MatchEvent {
  const PlaceVillage(this.vertex);
  final int vertex;
  @override
  Map<String, Object?> toJson() => {'type': 'village', 'vertex': vertex};
}

class PlaceRoad extends MatchEvent {
  const PlaceRoad(this.edge);
  final int edge;
  @override
  Map<String, Object?> toJson() => {'type': 'road', 'edge': edge};
}

class UpgradeSite extends MatchEvent {
  const UpgradeSite(this.vertex);
  final int vertex;
  @override
  Map<String, Object?> toJson() => {'type': 'upgrade', 'vertex': vertex};
}

class RollDice extends MatchEvent {
  const RollDice(this.first, this.second);
  final int first, second;
  @override
  Map<String, Object?> toJson() => {
    'type': 'roll',
    'first': first,
    'second': second,
  };
}

class MoveBandit extends MatchEvent {
  const MoveBandit(this.tile, {this.victim});
  final int tile;
  final int? victim;
  @override
  Map<String, Object?> toJson() => {
    'type': 'bandit',
    'tile': tile,
    'victim': victim,
  };
}

class BankExchange extends MatchEvent {
  const BankExchange(this.give, this.receive);
  final Resource give, receive;
  @override
  Map<String, Object?> toJson() => {
    'type': 'bank',
    'give': give.name,
    'receive': receive.name,
  };
}

class ProposeTrade extends MatchEvent {
  const ProposeTrade(
    this.target,
    this.give,
    this.giveCount,
    this.want,
    this.wantCount,
  );
  final int target, giveCount, wantCount;
  final Resource give, want;
  @override
  Map<String, Object?> toJson() => {
    'type': 'offer',
    'target': target,
    'give': give.name,
    'giveCount': giveCount,
    'want': want.name,
    'wantCount': wantCount,
  };
}

class RespondTrade extends MatchEvent {
  const RespondTrade(this.player, this.accept);
  final int player;
  final bool accept;
  @override
  Map<String, Object?> toJson() => {
    'type': 'answer',
    'player': player,
    'accept': accept,
  };
}

class DevelopTown extends MatchEvent {
  const DevelopTown(this.track);
  final StrategyDeck track;
  @override
  Map<String, Object?> toJson() => {'type': 'develop', 'track': track.name};
}

class FortifyTown extends MatchEvent {
  const FortifyTown(this.vertex);
  final int vertex;
  @override
  Map<String, Object?> toJson() => {'type': 'fortify', 'vertex': vertex};
}

class RecruitKnight extends MatchEvent {
  const RecruitKnight(this.vertex);
  final int vertex;
  @override
  Map<String, Object?> toJson() => {'type': 'recruit', 'vertex': vertex};
}

class ActivateKnight extends MatchEvent {
  const ActivateKnight(this.vertex);
  final int vertex;
  @override
  Map<String, Object?> toJson() => {'type': 'activate', 'vertex': vertex};
}

class PromoteKnight extends MatchEvent {
  const PromoteKnight(this.vertex);
  final int vertex;
  @override
  Map<String, Object?> toJson() => {'type': 'promote', 'vertex': vertex};
}

class MoveKnight extends MatchEvent {
  const MoveKnight(this.from, this.to);
  final int from, to;
  @override
  Map<String, Object?> toJson() => {
    'type': 'knightMove',
    'from': from,
    'to': to,
  };
}

class ResolveInvasion extends MatchEvent {
  const ResolveInvasion();
  @override
  Map<String, Object?> toJson() => {'type': 'invasion'};
}

class EndTurn extends MatchEvent {
  const EndTurn();
  @override
  Map<String, Object?> toJson() => {'type': 'end'};
}

class MatchState {
  MatchState({
    required this.seed,
    required this.board,
    required this.topology,
    required List<PlayerState> players,
    Map<int, Site> sites = const {},
    Map<int, int> roads = const {},
    Map<Resource, int> bank = const {},
    this.phase = MatchPhase.setupVillage,
    this.active = 0,
    this.setupStep = 0,
    this.pendingVillage,
    this.dice,
    this.rollCount = 0,
    this.banditTile = 0,
    this.round = 1,
    this.longestRoadHolder,
    Map<int, KnightPiece> knights = const {},
    Set<int> fortified = const {},
    Set<int> reaverScars = const {},
    Map<int, int> dryRolls = const {},
    Set<int> reliefUsed = const {},
    this.reaverPressure = 0,
    this.invasions = 0,
    this.turnSerial = 0,
    this.firstCapitalOwner,
    this.lastInvasion = '',
    Set<int> catchupUsed = const {},
    this.trade,
    List<MatchEvent> events = const [],
  }) : players = List.unmodifiable(players),
       sites = Map.unmodifiable(sites),
       roads = Map.unmodifiable(roads),
       knights = Map.unmodifiable(knights),
       fortified = Set.unmodifiable(fortified),
       reaverScars = Set.unmodifiable(reaverScars),
       dryRolls = Map.unmodifiable(dryRolls),
       reliefUsed = Set.unmodifiable(reliefUsed),
       bank = Map.unmodifiable(bank),
       catchupUsed = Set.unmodifiable(catchupUsed),
       events = List.unmodifiable(events);

  final int seed, active, setupStep, rollCount, banditTile, round;
  final Board board;
  final BoardTopology topology;
  final List<PlayerState> players;
  final Map<int, Site> sites;
  final Map<int, int> roads;
  final Map<int, KnightPiece> knights;
  final Set<int> fortified, reaverScars, reliefUsed;
  final Map<int, int> dryRolls;
  final int reaverPressure, invasions, turnSerial;
  final int? firstCapitalOwner;
  final String lastInvasion;
  final Map<Resource, int> bank;
  final MatchPhase phase;
  final int? pendingVillage, dice, longestRoadHolder;
  final Set<int> catchupUsed;
  final TradeProposal? trade;
  final List<MatchEvent> events;

  PlayerState get current => players[active];

  MatchState copyWith({
    List<PlayerState>? players,
    Map<int, Site>? sites,
    Map<int, int>? roads,
    Map<int, KnightPiece>? knights,
    Set<int>? fortified,
    Set<int>? reaverScars,
    Set<int>? reliefUsed,
    Map<int, int>? dryRolls,
    int? reaverPressure,
    int? invasions,
    int? turnSerial,
    int? firstCapitalOwner,
    String? lastInvasion,
    Map<Resource, int>? bank,
    MatchPhase? phase,
    int? active,
    int? setupStep,
    int? pendingVillage,
    bool clearPendingVillage = false,
    int? dice,
    bool clearDice = false,
    int? rollCount,
    int? banditTile,
    int? round,
    int? longestRoadHolder,
    bool clearRoadHolder = false,
    Set<int>? catchupUsed,
    TradeProposal? trade,
    bool clearTrade = false,
    List<MatchEvent>? events,
  }) => MatchState(
    seed: seed,
    board: board,
    topology: topology,
    players: players ?? this.players,
    sites: sites ?? this.sites,
    roads: roads ?? this.roads,
    knights: knights ?? this.knights,
    fortified: fortified ?? this.fortified,
    reaverScars: reaverScars ?? this.reaverScars,
    reliefUsed: reliefUsed ?? this.reliefUsed,
    dryRolls: dryRolls ?? this.dryRolls,
    reaverPressure: reaverPressure ?? this.reaverPressure,
    invasions: invasions ?? this.invasions,
    turnSerial: turnSerial ?? this.turnSerial,
    firstCapitalOwner: firstCapitalOwner ?? this.firstCapitalOwner,
    lastInvasion: lastInvasion ?? this.lastInvasion,
    bank: bank ?? this.bank,
    phase: phase ?? this.phase,
    active: active ?? this.active,
    setupStep: setupStep ?? this.setupStep,
    pendingVillage: clearPendingVillage
        ? null
        : pendingVillage ?? this.pendingVillage,
    dice: clearDice ? null : dice ?? this.dice,
    rollCount: rollCount ?? this.rollCount,
    banditTile: banditTile ?? this.banditTile,
    round: round ?? this.round,
    longestRoadHolder: clearRoadHolder
        ? null
        : longestRoadHolder ?? this.longestRoadHolder,
    catchupUsed: catchupUsed ?? this.catchupUsed,
    trade: clearTrade ? null : trade ?? this.trade,
    events: events ?? this.events,
  );
}

/// Pure reducer: every state change is one validated event. Replay uses the
/// identical reducer, including seeded dice and Bandit theft selection.
class MatchEngine {
  static const bankSupply = 19;
  static const roadLimit = 15;
  static const roadCost = {Resource.wood: 1, Resource.brick: 1};
  static Map<Resource, int> effectiveRoadCost(MatchState s) =>
      s.current.level(StrategyDeck.innovation) >= 2
      ? {Resource.wood: 1}
      : roadCost;
  static const villageCost = {
    Resource.wood: 1,
    Resource.brick: 1,
    Resource.wheat: 1,
    Resource.wool: 1,
  };
  static const townCost = {Resource.wheat: 2, Resource.ore: 3};
  static const capitalCost = {
    Resource.wheat: 2,
    Resource.ore: 2,
    Resource.paper: 1,
    Resource.cloth: 1,
    Resource.coin: 1,
  };
  static const fortCost = {Resource.brick: 2, Resource.coin: 1};
  static const recruitCost = {Resource.wool: 1, Resource.ore: 1};
  static const activateCost = {Resource.wheat: 1};
  static const rebuildCost = {Resource.wheat: 1, Resource.ore: 2};

  static void _require(bool condition, String reason) {
    if (!condition) throw StateError(reason);
  }

  static MatchState newGame(List<String> names, int seed) {
    _require(names.length >= 3 && names.length <= 4, 'Choose 3 or 4 players.');
    _require(
      names.every((n) => n.trim().isNotEmpty) &&
          names.toSet().length == names.length,
      'Use distinct player names.',
    );
    final board = BoardGenerator.generate(seed);
    return MatchState(
      seed: seed,
      board: board,
      topology: BoardTopology(board),
      players: [for (final n in names) PlayerState(id: n)],
      bank: {for (final r in Resource.values) r: bankSupply},
      banditTile: board.tiles.indexWhere((tile) => tile.land == Land.barren),
    );
  }

  static MatchState replay(
    List<String> names,
    int seed,
    Iterable<MatchEvent> events,
  ) {
    var state = newGame(names, seed);
    for (final event in events) {
      state = apply(state, event);
    }
    return state;
  }

  static String exportReplay(MatchState s) => jsonEncode({
    'format': 'stone-and-banner-replay-v1',
    'seed': s.seed,
    'names': [for (final p in s.players) p.id],
    'events': [for (final e in s.events) e.toJson()],
  });

  static MatchState importReplay(String json) {
    final value = jsonDecode(json) as Map<String, dynamic>;
    _require(
      value['format'] == 'stone-and-banner-replay-v1',
      'Unknown replay format.',
    );
    final names = (value['names'] as List).cast<String>();
    final events = (value['events'] as List).map((item) {
      final e = item as Map<String, dynamic>;
      final type = e['type'] as String;
      Resource resource(String key) => Resource.values.byName(e[key] as String);
      return switch (type) {
        'village' => PlaceVillage(e['vertex'] as int),
        'road' => PlaceRoad(e['edge'] as int),
        'upgrade' => UpgradeSite(e['vertex'] as int),
        'develop' => DevelopTown(
          StrategyDeck.values.byName(e['track'] as String),
        ),
        'fortify' => FortifyTown(e['vertex'] as int),
        'recruit' => RecruitKnight(e['vertex'] as int),
        'activate' => ActivateKnight(e['vertex'] as int),
        'promote' => PromoteKnight(e['vertex'] as int),
        'knightMove' => MoveKnight(e['from'] as int, e['to'] as int),
        'invasion' => const ResolveInvasion(),
        'roll' => RollDice(e['first'] as int, e['second'] as int),
        'bandit' => MoveBandit(e['tile'] as int, victim: e['victim'] as int?),
        'bank' => BankExchange(resource('give'), resource('receive')),
        'offer' => ProposeTrade(
          e['target'] as int,
          resource('give'),
          e['giveCount'] as int,
          resource('want'),
          e['wantCount'] as int,
        ),
        'answer' => RespondTrade(e['player'] as int, e['accept'] as bool),
        'end' => const EndTurn(),
        _ => throw FormatException('Unknown event type.'),
      };
    });
    return replay(names, value['seed'] as int, events);
  }

  static String snapshot(MatchState s) => jsonEncode({
    'seed': s.seed,
    'phase': s.phase.name,
    'active': s.active,
    'round': s.round,
    'step': s.setupStep,
    'pending': s.pendingVillage,
    'dice': s.dice,
    'rollCount': s.rollCount,
    'bandit': s.banditTile,
    'holder': s.longestRoadHolder,
    'pressure': s.reaverPressure,
    'invasions': s.invasions,
    'serial': s.turnSerial,
    'firstCapital': s.firstCapitalOwner,
    'lastInvasion': s.lastInvasion,
    'forts': s.fortified.toList()..sort(),
    'scars': s.reaverScars.toList()..sort(),
    'reliefUsed': s.reliefUsed.toList()..sort(),
    'dryRolls': [for (var i = 0; i < s.players.length; i++) s.dryRolls[i] ?? 0],
    'knights': [
      for (final v in (s.knights.keys.toList()..sort()))
        [
          v,
          s.knights[v]!.owner,
          s.knights[v]!.rank.name,
          s.knights[v]!.active,
          s.knights[v]!.actedTurn,
        ],
    ],
    'catchup': s.catchupUsed.toList()..sort(),
    'bank': [for (final r in Resource.values) s.bank[r] ?? 0],
    'players': [
      for (final p in s.players)
        {
          'name': p.id,
          'resources': [for (final r in Resource.values) p.stores[r] ?? 0],
          'score': GameEngine.score(p),
          'honour': p.guardianHonour,
          'charters': p.charterPoints,
          'developments': [for (final t in StrategyDeck.values) p.level(t)],
        },
    ],
    'sites': [
      for (final key in (s.sites.keys.toList()..sort()))
        [key, s.sites[key]!.owner, s.sites[key]!.structure.name],
    ],
    'roads': [
      for (final key in (s.roads.keys.toList()..sort())) [key, s.roads[key]],
    ],
    'trade': s.trade == null
        ? null
        : [
            s.trade!.target,
            s.trade!.give.name,
            s.trade!.giveCount,
            s.trade!.want.name,
            s.trade!.wantCount,
          ],
    'events': [for (final e in s.events) e.toJson()],
  });

  static int score(MatchState s, int player) =>
      GameEngine.score(s.players[player]) +
      (s.longestRoadHolder == player ? 2 : 0);

  static int? winner(MatchState s) {
    for (var i = 0; i < s.players.length; i++) {
      if (score(s, i) >= GameEngine.winningPoints) return i;
    }
    return null;
  }

  static int tradeRate(MatchState s, int player) {
    final best = [for (var i = 0; i < s.players.length; i++) score(s, i)]
        .reduce((a, b) => a > b ? a : b);
    final commerce = s.players[player].level(StrategyDeck.commerce);
    if (commerce >= 4) return 2;
    if (commerce >= 2) return 3;
    return best - score(s, player) >= 3 && !s.catchupUsed.contains(player)
        ? 3
        : 4;
  }

  static bool affordable(MatchState s, Map<Resource, int> cost, [int? player]) {
    final goods = s.players[player ?? s.active].stores;
    return cost.entries.every((e) => (goods[e.key] ?? 0) >= e.value);
  }

  static bool legalVillage(MatchState s, int vertex) {
    if (vertex < 0 ||
        vertex >= s.topology.vertices.length ||
        s.sites.containsKey(vertex)) {
      return false;
    }
    if (s.topology.neighbours(vertex).any(s.sites.containsKey)) return false;
    if (s.phase == MatchPhase.setupVillage) return true;
    if (s.phase != MatchPhase.actions ||
        s.trade != null ||
        !affordable(s, villageCost)) {
      return false;
    }
    return s.topology.vertices[vertex].edges.any((e) => s.roads[e] == s.active);
  }

  static bool legalRoad(MatchState s, int edge) {
    if (edge < 0 ||
        edge >= s.topology.edges.length ||
        s.roads.containsKey(edge)) {
      return false;
    }
    if (s.roads.values.where((p) => p == s.active).length >= roadLimit) {
      return false;
    }
    final e = s.topology.edges[edge];
    if (s.phase == MatchPhase.setupRoad) {
      return e.a == s.pendingVillage || e.b == s.pendingVillage;
    }
    if (s.phase != MatchPhase.actions ||
        s.trade != null ||
        !affordable(s, effectiveRoadCost(s))) {
      return false;
    }
    bool linked(int vertex) {
      if (s.sites[vertex] case final Site site) return site.owner == s.active;
      return s.topology.vertices[vertex].edges.any(
        (other) => s.roads[other] == s.active,
      );
    }

    return linked(e.a) || linked(e.b);
  }

  static bool legalUpgrade(MatchState s, int vertex) {
    if (s.phase != MatchPhase.actions || s.trade != null) return false;
    final site = s.sites[vertex];
    if (site == null ||
        site.owner != s.active ||
        site.structure == Structure.capital) {
      return false;
    }
    return affordable(
      s,
      site.structure == Structure.village
          ? (s.reaverScars.contains(vertex) ? rebuildCost : townCost)
          : capitalCost,
    );
  }

  static bool canDevelop(MatchState s, StrategyDeck track) {
    final level = s.current.level(track);
    return s.phase == MatchPhase.actions &&
        s.trade == null &&
        level < 5 &&
        s.sites.values.any(
          (site) =>
              site.owner == s.active && site.structure != Structure.village,
        ) &&
        affordable(s, track.costFor(level + 1));
  }

  static bool legalFort(MatchState s, int vertex) =>
      s.phase == MatchPhase.actions &&
      s.trade == null &&
      s.sites[vertex]?.owner == s.active &&
      s.sites[vertex]!.structure != Structure.village &&
      !s.fortified.contains(vertex) &&
      affordable(s, fortCost);

  static bool legalRecruit(MatchState s, int vertex) {
    if (s.phase != MatchPhase.actions ||
        s.trade != null ||
        vertex < 0 ||
        vertex >= s.topology.vertices.length ||
        s.knights.containsKey(vertex) ||
        (s.sites[vertex] != null && s.sites[vertex]!.owner != s.active) ||
        s.knights.values.where((k) => k.owner == s.active).length >= 3 ||
        !affordable(
          s,
          s.current.level(StrategyDeck.governance) >= 4
              ? {Resource.wool: 1}
              : recruitCost,
        )) {
      return false;
    }
    return s.topology.vertices[vertex].edges.any((e) => s.roads[e] == s.active);
  }

  static bool legalActivate(MatchState s, int vertex) {
    final knight = s.knights[vertex];
    return s.phase == MatchPhase.actions &&
        s.trade == null &&
        knight != null &&
        knight.owner == s.active &&
        !knight.active &&
        knight.actedTurn != s.turnSerial &&
        affordable(s, activateCost);
  }

  static Map<Resource, int> promotionCost(KnightRank rank) => switch (rank) {
    KnightRank.sentinel => {Resource.ore: 1, Resource.wool: 1},
    KnightRank.warden => {Resource.ore: 2, Resource.coin: 1},
    KnightRank.champion => {},
  };

  static bool legalPromote(MatchState s, int vertex) {
    final knight = s.knights[vertex];
    return s.phase == MatchPhase.actions &&
        s.trade == null &&
        knight != null &&
        knight.owner == s.active &&
        knight.active &&
        knight.rank != KnightRank.champion &&
        knight.actedTurn != s.turnSerial &&
        affordable(s, promotionCost(knight.rank));
  }

  static bool legalMoveKnight(MatchState s, int from, int to) {
    final knight = s.knights[from], occupant = s.knights[to];
    if (s.phase != MatchPhase.actions ||
        s.trade != null ||
        knight == null ||
        knight.owner != s.active ||
        !knight.active ||
        knight.actedTurn == s.turnSerial ||
        to < 0 ||
        to >= s.topology.vertices.length ||
        from == to ||
        (s.sites[to] != null && s.sites[to]!.owner != s.active) ||
        (occupant != null &&
            (occupant.owner == s.active ||
                occupant.rank.strength >= knight.rank.strength))) {
      return false;
    }
    return s.topology.vertices[from].edges.any((id) {
      final edge = s.topology.edges[id];
      return s.roads[id] == s.active && (edge.a == to || edge.b == to);
    });
  }

  static List<int> legalKnightDestinations(MatchState s, int from) => [
    for (var v = 0; v < s.topology.vertices.length; v++)
      if (legalMoveKnight(s, from, v)) v,
  ];

  static int invasionStrength(MatchState s) =>
      4 + s.invasions + (s.reaverPressure > 3 ? s.reaverPressure - 3 : 0);

  static int defenceStrength(MatchState s) =>
      s.knights.values
          .where((k) => k.active)
          .fold<int>(0, (total, k) => total + k.rank.strength) +
      s.fortified.length +
      s.players.where((p) => p.level(StrategyDeck.governance) >= 2).length +
      s.players.where((p) => p.level(StrategyDeck.governance) >= 5).length +
      s.players.where((p) => p.level(StrategyDeck.innovation) >= 5).length;

  static List<int> legalVertices(MatchState s) => [
    for (var v = 0; v < s.topology.vertices.length; v++)
      if (legalVillage(s, v)) v,
  ];

  static List<int> legalEdges(MatchState s) => [
    for (var e = 0; e < s.topology.edges.length; e++)
      if (legalRoad(s, e)) e,
  ];

  static List<int> legalUpgrades(MatchState s) => [
    for (final v in s.sites.keys)
      if (legalUpgrade(s, v)) v,
  ];

  static int _random(int seed) {
    var x = seed & 0xffffffff;
    if (x == 0) x = 0x6d2b79f5;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    return x & 0xffffffff;
  }

  static (int, int) expectedDice(MatchState s) {
    final a = _random(s.seed ^ 0x9e3779b9 ^ ((s.rollCount + 1) * 0x85ebca6b));
    final b = _random(a ^ 0xc2b2ae35);
    return (a % 6 + 1, b % 6 + 1);
  }

  static MatchState roll(MatchState s) {
    final (a, b) = expectedDice(s);
    return apply(s, RollDice(a, b));
  }

  static List<int> banditVictims(MatchState s, int tile) {
    _require(tile >= 0 && tile < s.board.tiles.length, 'Unknown tile.');
    return [
      for (var i = 0; i < s.players.length; i++)
        if (i != s.active &&
            s.topology.tileVertices[tile].any((v) => s.sites[v]?.owner == i) &&
            s.players[i].stores.values.any((n) => n > 0))
          i,
    ];
  }

  static int longestRoad(MatchState s, int player) {
    final owned = {
      for (final e in s.roads.keys)
        if (s.roads[e] == player) e,
    };
    if (owned.isEmpty) return 0;
    var best = 0;
    void walk(int vertex, Set<int> used, int length) {
      if (length > best) best = length;
      if (length > 0 &&
          s.sites[vertex] != null &&
          s.sites[vertex]!.owner != player) {
        return;
      }
      for (final edge in s.topology.vertices[vertex].edges) {
        if (!owned.contains(edge) || used.contains(edge)) continue;
        final e = s.topology.edges[edge];
        used.add(edge);
        walk(e.a == vertex ? e.b : e.a, used, length + 1);
        used.remove(edge);
      }
    }

    for (final edge in owned) {
      final e = s.topology.edges[edge];
      walk(e.a, {}, 0);
      walk(e.b, {}, 0);
    }
    return best;
  }

  static MatchState _recalculateRoads(MatchState s) {
    final lengths = [
      for (var i = 0; i < s.players.length; i++) longestRoad(s, i),
    ];
    final largest = lengths.reduce((a, b) => a > b ? a : b);
    if (largest < 5) return s.copyWith(clearRoadHolder: true);
    final tied = [
      for (var i = 0; i < lengths.length; i++)
        if (lengths[i] == largest) i,
    ];
    final holder = tied.length == 1
        ? tied.single
        : tied.contains(s.longestRoadHolder)
        ? s.longestRoadHolder
        : null;
    return holder == null
        ? s.copyWith(clearRoadHolder: true)
        : s.copyWith(longestRoadHolder: holder);
  }

  static MatchState _syncBuildings(MatchState s) => s.copyWith(
    players: [
      for (var i = 0; i < s.players.length; i++)
        s.players[i].copyWith(
          buildings: [
            for (final site in s.sites.values)
              if (site.owner == i) site.structure,
          ],
        ),
    ],
  );

  static MatchState _pay(MatchState s, Map<Resource, int> cost) {
    _require(affordable(s, cost), 'Not enough goods.');
    final stores = Map<Resource, int>.of(s.current.stores);
    final bank = Map<Resource, int>.of(s.bank);
    for (final e in cost.entries) {
      stores[e.key] = (stores[e.key] ?? 0) - e.value;
      bank[e.key] = (bank[e.key] ?? 0) + e.value;
    }
    final players = List<PlayerState>.of(s.players);
    players[s.active] = s.current.copyWith(stores: stores);
    return s.copyWith(players: players, bank: bank);
  }

  static MatchState _produce(MatchState s, int number) {
    final claims = <Resource, Map<int, int>>{};
    void claim(Resource resource, int player, int count) {
      if (count == 0) return;
      final recipients = claims.putIfAbsent(resource, () => {});
      recipients[player] = (recipients[player] ?? 0) + count;
    }

    for (var tile = 0; tile < s.board.tiles.length; tile++) {
      final t = s.board.tiles[tile];
      if (tile == s.banditTile || t.productionNumber != number) continue;
      final good = t.land.produces;
      if (good == null) continue;
      for (final vertex in s.topology.tileVertices[tile]) {
        final site = s.sites[vertex];
        if (site == null) continue;
        var basic = switch (site.structure) {
          Structure.village => 1,
          Structure.town => 2,
          Structure.capital => 3,
        };
        if (site.structure != Structure.village) {
          for (final track in StrategyDeck.values) {
            final level = s.players[site.owner].level(track);
            if (level > 0 && track.sourceLand == t.land) {
              final converted = level == 5 ? 2 : 1;
              claim(track.commodity, site.owner, converted);
              basic -= converted;
              break;
            }
          }
        }
        claim(good, site.owner, basic);
      }
    }

    final bank = Map<Resource, int>.of(s.bank);
    final players = List<PlayerState>.of(s.players);
    final produced = List<int>.filled(players.length, 0);
    for (final entry in claims.entries) {
      final total = entry.value.values.fold<int>(0, (a, b) => a + b);
      // Shortage blocks everyone equally; never pay in seat order.
      if ((bank[entry.key] ?? 0) < total) continue;
      bank[entry.key] = bank[entry.key]! - total;
      for (final receipt in entry.value.entries) {
        final p = players[receipt.key];
        final stores = Map<Resource, int>.of(p.stores);
        stores[entry.key] = (stores[entry.key] ?? 0) + receipt.value;
        players[receipt.key] = p.copyWith(stores: stores);
        produced[receipt.key] += receipt.value;
      }
    }

    final dry = Map<int, int>.of(s.dryRolls);
    final relieved = Set<int>.of(s.reliefUsed);
    final leader = [for (var i = 0; i < s.players.length; i++) score(s, i)]
        .reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < players.length; i++) {
      dry[i] = produced[i] > 0 ? 0 : (dry[i] ?? 0) + 1;
      final innovation = players[i].level(StrategyDeck.innovation);
      final threshold = innovation >= 3 ? 2 : 3;
      if (dry[i]! < threshold ||
          relieved.contains(i) ||
          leader - score(s, i) < 3) {
        continue;
      }
      Resource? chosen;
      if (innovation >= 4) {
        final candidates =
            Resource.values.take(5).where((r) => bank[r]! > 0).toList()
              ..sort((a, b) {
                final byCount = (players[i].stores[a] ?? 0).compareTo(
                  players[i].stores[b] ?? 0,
                );
                return byCount != 0 ? byCount : a.index.compareTo(b.index);
              });
        if (candidates.isNotEmpty) chosen = candidates.first;
      } else if (bank[Resource.wheat]! > 0) {
        chosen = Resource.wheat;
      }
      if (chosen != null) {
        bank[chosen] = bank[chosen]! - 1;
        final stores = Map<Resource, int>.of(players[i].stores);
        stores[chosen] = (stores[chosen] ?? 0) + 1;
        players[i] = players[i].copyWith(stores: stores);
        relieved.add(i);
        dry[i] = 0;
      }
    }
    return s.copyWith(
      players: players,
      bank: bank,
      dryRolls: dry,
      reliefUsed: relieved,
    );
  }

  static MatchState _discardOnSeven(MatchState s) {
    final bank = Map<Resource, int>.of(s.bank);
    final players = List<PlayerState>.of(s.players);
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      final hand = Map<Resource, int>.of(p.stores);
      final total = Resource.values.fold<int>(
        0,
        (sum, r) => sum + (hand[r] ?? 0),
      );
      final forts = s.fortified.where((v) => s.sites[v]?.owner == i).length;
      final capacity =
          7 +
          forts * 2 +
          (p.level(StrategyDeck.governance) >= 3 ? 2 : 0) +
          (p.level(StrategyDeck.commerce) >= 3 ? 2 : 0);
      if (total <= capacity) continue;
      for (var count = total ~/ 2; count > 0; count--) {
        final goods = Resource.values.where((r) => (hand[r] ?? 0) > 0).toList()
          ..sort((a, b) {
            final amount = (hand[b] ?? 0).compareTo(hand[a] ?? 0);
            return amount != 0 ? amount : a.index.compareTo(b.index);
          });
        final good = goods.first;
        hand[good] = hand[good]! - 1;
        bank[good] = bank[good]! + 1;
      }
      players[i] = p.copyWith(stores: hand);
    }
    return s.copyWith(players: players, bank: bank);
  }

  static MatchState _resolveInvasion(MatchState s) {
    final strength = defenceStrength(s), threat = invasionStrength(s);
    var report = '';
    var result = s;
    if (strength >= threat) {
      final contributions = <int, int>{
        for (var i = 0; i < s.players.length; i++)
          i: s.knights.values
              .where((k) => k.owner == i && k.active)
              .fold<int>(0, (total, k) => total + k.rank.strength),
      };
      final peak = contributions.values.reduce((a, b) => a > b ? a : b);
      final leaders = contributions.keys
          .where((i) => peak > 0 && contributions[i] == peak)
          .toList();
      if (leaders.length == 1) {
        final index = leaders.single;
        final players = List<PlayerState>.of(s.players);
        players[index] = players[index].copyWith(
          guardianHonour: players[index].guardianHonour + 1,
        );
        result = result.copyWith(players: players);
        report =
            'Defended $strength–$threat. ${players[index].id} earns Guardian\'s Honour (+1 VP).';
      } else {
        report =
            'Defended $strength–$threat. No sole Knight leader; no Honour awarded.';
      }
    } else {
      final targets =
          s.sites.keys
              .where((v) => s.sites[v]!.structure != Structure.village)
              .toList()
            ..sort((a, b) {
              final owners = score(
                s,
                s.sites[b]!.owner,
              ).compareTo(score(s, s.sites[a]!.owner));
              return owners != 0 ? owners : a.compareTo(b);
            });
      if (targets.isNotEmpty) {
        final vertex = targets.first, site = s.sites[vertex]!;
        if (s.fortified.contains(vertex)) {
          result = result.copyWith(fortified: {...s.fortified}..remove(vertex));
          report =
              'Invasion $threat–$strength. Fortifications at $vertex held, then fell.';
        } else {
          final next = site.structure == Structure.capital
              ? Structure.town
              : Structure.village;
          result = _syncBuildings(
            result.copyWith(
              sites: {...s.sites, vertex: Site(site.owner, next)},
              reaverScars: {
                ...s.reaverScars,
                if (site.structure == Structure.town) vertex,
              },
            ),
          );
          if (s.players[site.owner].level(StrategyDeck.governance) < 3) {
            final bank = Map<Resource, int>.of(result.bank);
            final players = List<PlayerState>.of(result.players);
            final hand = Map<Resource, int>.of(players[site.owner].stores);
            for (var n = 0; n < 2; n++) {
              final goods = Resource.values
                  .where((r) => (hand[r] ?? 0) > 0)
                  .toList();
              if (goods.isEmpty) break;
              goods.sort((a, b) {
                final quantity = (hand[b] ?? 0).compareTo(hand[a] ?? 0);
                return quantity != 0 ? quantity : a.index.compareTo(b.index);
              });
              final good = goods.first;
              hand[good] = hand[good]! - 1;
              bank[good] = bank[good]! + 1;
            }
            players[site.owner] = players[site.owner].copyWith(stores: hand);
            result = result.copyWith(players: players, bank: bank);
          }
          report =
              'Invasion $threat–$strength. ${s.players[site.owner].id} lost a ${site.structure.name} at $vertex.';
        }
      } else {
        report = 'Invasion $threat–$strength. No Town to raid.';
      }
    }
    return result.copyWith(
      phase: MatchPhase.roll,
      invasions: s.invasions + 1,
      reaverPressure: 0,
      lastInvasion: report,
    );
  }

  static MatchState _awardSetupGoods(MatchState s, int vertex) {
    final supplies = <Resource, int>{};
    for (final tile in s.topology.vertices[vertex].tiles) {
      final good = s.board.tiles[tile].land.produces;
      if (good != null) supplies[good] = (supplies[good] ?? 0) + 1;
    }
    final bank = Map<Resource, int>.of(s.bank);
    final stores = Map<Resource, int>.of(s.current.stores);
    for (final e in supplies.entries) {
      final amount = e.value < (bank[e.key] ?? 0) ? e.value : bank[e.key] ?? 0;
      stores[e.key] = (stores[e.key] ?? 0) + amount;
      bank[e.key] = bank[e.key]! - amount;
    }
    final players = List<PlayerState>.of(s.players);
    players[s.active] = s.current.copyWith(stores: stores);
    return s.copyWith(players: players, bank: bank);
  }

  static MatchState apply(MatchState state, MatchEvent event) {
    _require(
      state.phase != MatchPhase.finished && winner(state) == null,
      'Match is finished.',
    );
    _require(
      state.trade == null || event is RespondTrade,
      'Respond to the offer first.',
    );
    var s = state;

    if (event is PlaceVillage) {
      _require(
        legalVillage(s, event.vertex),
        'Village cannot be placed there.',
      );
      if (s.phase == MatchPhase.actions) s = _pay(s, villageCost);
      s = s.copyWith(
        sites: {...s.sites, event.vertex: Site(s.active, Structure.village)},
        phase: s.phase == MatchPhase.setupVillage
            ? MatchPhase.setupRoad
            : MatchPhase.actions,
        pendingVillage: s.phase == MatchPhase.setupVillage
            ? event.vertex
            : null,
        clearPendingVillage: s.phase != MatchPhase.setupVillage,
      );
      s = _recalculateRoads(_syncBuildings(s));
      if (state.phase == MatchPhase.setupVillage &&
          s.setupStep >= s.players.length) {
        s = _awardSetupGoods(s, event.vertex);
      }
    } else if (event is PlaceRoad) {
      _require(legalRoad(s, event.edge), 'Road must join your network.');
      final setup = s.phase == MatchPhase.setupRoad;
      if (!setup) s = _pay(s, effectiveRoadCost(s));
      s = s.copyWith(roads: {...s.roads, event.edge: s.active});
      s = _recalculateRoads(s);
      if (setup) {
        final next = s.setupStep + 1, count = s.players.length;
        final player = next >= count * 2
            ? 0
            : next < count
            ? next
            : count * 2 - 1 - next;
        s = s.copyWith(
          setupStep: next,
          active: player,
          clearPendingVillage: true,
          phase: next == count * 2 ? MatchPhase.roll : MatchPhase.setupVillage,
        );
      }
    } else if (event is UpgradeSite) {
      _require(legalUpgrade(s, event.vertex), 'Cannot upgrade that site.');
      final current = s.sites[event.vertex]!;
      final next = current.structure == Structure.village
          ? Structure.town
          : Structure.capital;
      s = _pay(
        s,
        next == Structure.town
            ? (s.reaverScars.contains(event.vertex) ? rebuildCost : townCost)
            : capitalCost,
      );
      final players = List<PlayerState>.of(s.players);
      var firstCapital = s.firstCapitalOwner;
      if (next == Structure.capital && firstCapital == null) {
        firstCapital = s.active;
        players[s.active] = s.current.copyWith(
          charterPoints: s.current.charterPoints + 1,
        );
      }
      s = _syncBuildings(
        s.copyWith(
          players: players,
          firstCapitalOwner: firstCapital,
          reaverScars: {...s.reaverScars}..remove(event.vertex),
          sites: {...s.sites, event.vertex: Site(s.active, next)},
        ),
      );
    } else if (event is DevelopTown) {
      _require(canDevelop(s, event.track), 'Cannot develop that track.');
      final level = s.current.level(event.track) + 1;
      s = _pay(s, event.track.costFor(level));
      final players = List<PlayerState>.of(s.players);
      players[s.active] = s.current.copyWith(
        developments: {...s.current.developments, event.track: level},
      );
      s = s.copyWith(players: players);
    } else if (event is FortifyTown) {
      _require(legalFort(s, event.vertex), 'Cannot fortify that Town.');
      s = _pay(s, fortCost);
      s = s.copyWith(fortified: {...s.fortified, event.vertex});
    } else if (event is RecruitKnight) {
      _require(legalRecruit(s, event.vertex), 'Cannot recruit there.');
      s = _pay(
        s,
        s.current.level(StrategyDeck.governance) >= 4
            ? {Resource.wool: 1}
            : recruitCost,
      );
      s = s.copyWith(
        knights: {
          ...s.knights,
          event.vertex: KnightPiece(
            s.active,
            KnightRank.sentinel,
            false,
            s.turnSerial,
          ),
        },
      );
    } else if (event is ActivateKnight) {
      _require(legalActivate(s, event.vertex), 'Cannot activate that Knight.');
      s = _pay(s, activateCost);
      s = s.copyWith(
        knights: {
          ...s.knights,
          event.vertex: s.knights[event.vertex]!.copyWith(
            active: true,
            actedTurn: s.turnSerial,
          ),
        },
      );
    } else if (event is PromoteKnight) {
      _require(legalPromote(s, event.vertex), 'Cannot promote that Knight.');
      final knight = s.knights[event.vertex]!;
      s = _pay(s, promotionCost(knight.rank));
      s = s.copyWith(
        knights: {
          ...s.knights,
          event.vertex: knight.copyWith(
            rank: KnightRank.values[knight.rank.index + 1],
            actedTurn: s.turnSerial,
          ),
        },
      );
    } else if (event is MoveKnight) {
      _require(
        legalMoveKnight(s, event.from, event.to),
        'Knight movement is not legal.',
      );
      final moving = s.knights[event.from]!;
      final knights = Map<int, KnightPiece>.of(s.knights)..remove(event.from);
      final displaced = knights.remove(event.to);
      if (displaced != null) {
        final choices =
            s.topology.vertices[event.to].edges
                .where((e) => s.roads[e] == displaced.owner)
                .map((e) {
                  final side = s.topology.edges[e];
                  return side.a == event.to ? side.b : side.a;
                })
                .where(
                  (v) =>
                      !knights.containsKey(v) &&
                      v != event.from &&
                      s.sites[v]?.owner != s.active,
                )
                .toList()
              ..sort();
        if (choices.isNotEmpty) {
          knights[choices.first] = displaced.copyWith(active: false);
        }
      }
      knights[event.to] = moving.copyWith(actedTurn: s.turnSerial);
      s = s.copyWith(knights: knights);
    } else if (event is ResolveInvasion) {
      _require(s.phase == MatchPhase.invasion, 'No Invasion to resolve.');
      s = _resolveInvasion(s);
      s = _recalculateRoads(s);
    } else if (event is RollDice) {
      _require(
        s.phase == MatchPhase.roll,
        'You can roll only once at turn start.',
      );
      final expected = expectedDice(s);
      _require(
        event.first == expected.$1 && event.second == expected.$2,
        'Dice must match the saved seed and roll index.',
      );
      final value = event.first + event.second;
      s = s.copyWith(
        dice: value,
        rollCount: s.rollCount + 1,
        phase: value == 7 ? MatchPhase.bandit : MatchPhase.actions,
      );
      if (value != 7) {
        s = _produce(s, value);
      } else {
        s = _discardOnSeven(s).copyWith(reaverPressure: s.reaverPressure + 1);
      }
    } else if (event is MoveBandit) {
      _require(s.phase == MatchPhase.bandit, 'Bandit moves only after seven.');
      _require(
        event.tile >= 0 &&
            event.tile < s.board.tiles.length &&
            event.tile != s.banditTile,
        'Choose another tile.',
      );
      final eligible = banditVictims(s, event.tile);
      _require(
        event.victim == null || eligible.contains(event.victim),
        'Victim must have goods and border the selected tile.',
      );
      var players = List<PlayerState>.of(s.players);
      if (event.victim case final int victim) {
        final target = players[victim];
        final goods = [
          for (final resource in Resource.values)
            for (var n = 0; n < (target.stores[resource] ?? 0); n++) resource,
        ];
        final index = _random(
          s.seed ^ s.rollCount ^ (event.tile << 16) ^ victim,
        );
        final stolen = goods[index % goods.length];
        final from = Map<Resource, int>.of(target.stores);
        final to = Map<Resource, int>.of(s.current.stores);
        from[stolen] = from[stolen]! - 1;
        to[stolen] = (to[stolen] ?? 0) + 1;
        players[victim] = target.copyWith(stores: from);
        players[s.active] = s.current.copyWith(stores: to);
      }
      s = s.copyWith(
        players: players,
        banditTile: event.tile,
        phase: MatchPhase.actions,
      );
    } else if (event is BankExchange) {
      _require(s.phase == MatchPhase.actions, 'Trade after rolling.');
      _require(event.give != event.receive, 'Choose different goods.');
      _require(
        event.receive.index < Resource.values.length &&
            event.give.index < Resource.values.length,
        'Unknown goods.',
      );
      final rate = tradeRate(s, s.active);
      _require(
        (s.current.stores[event.give] ?? 0) >= rate,
        'Not enough goods.',
      );
      final commerce = s.current.level(StrategyDeck.commerce);
      final count =
          commerce >= 5 || (commerce >= 3 && event.receive == Resource.cloth)
          ? 2
          : 1;
      _require((s.bank[event.receive] ?? 0) >= count, 'Bank stock exhausted.');
      final stores = Map<Resource, int>.of(s.current.stores);
      final bank = Map<Resource, int>.of(s.bank);
      stores[event.give] = stores[event.give]! - rate;
      stores[event.receive] = (stores[event.receive] ?? 0) + count;
      bank[event.give] = bank[event.give]! + rate;
      bank[event.receive] = bank[event.receive]! - count;
      final players = List<PlayerState>.of(s.players);
      players[s.active] = s.current.copyWith(stores: stores);
      s = s.copyWith(
        players: players,
        bank: bank,
        catchupUsed: {
          ...s.catchupUsed,
          if (rate == 3 && s.current.level(StrategyDeck.commerce) < 2) s.active,
        },
      );
    } else if (event is ProposeTrade) {
      _require(s.phase == MatchPhase.actions, 'Trade after rolling.');
      _require(
        event.target >= 0 &&
            event.target < s.players.length &&
            event.target != s.active,
        'Choose another player.',
      );
      _require(
        event.give != event.want && event.giveCount > 0 && event.wantCount > 0,
        'Invalid offer.',
      );
      _require(
        (s.current.stores[event.give] ?? 0) >= event.giveCount,
        'You cannot offer goods you do not have.',
      );
      _require(
        (s.players[event.target].stores[event.want] ?? 0) >= event.wantCount,
        'Recipient lacks the requested goods.',
      );
      s = s.copyWith(
        trade: TradeProposal(
          event.target,
          event.give,
          event.giveCount,
          event.want,
          event.wantCount,
        ),
      );
    } else if (event is RespondTrade) {
      final offer = s.trade;
      _require(offer != null, 'No outstanding trade offer.');
      _require(event.player == offer!.target, 'Only the recipient can answer.');
      if (event.accept) {
        final buyer = s.current, seller = s.players[event.player];
        _require(
          (buyer.stores[offer.give] ?? 0) >= offer.giveCount &&
              (seller.stores[offer.want] ?? 0) >= offer.wantCount,
          'Goods no longer available.',
        );
        final a = Map<Resource, int>.of(buyer.stores);
        final b = Map<Resource, int>.of(seller.stores);
        a[offer.give] = a[offer.give]! - offer.giveCount;
        a[offer.want] = (a[offer.want] ?? 0) + offer.wantCount;
        b[offer.want] = b[offer.want]! - offer.wantCount;
        b[offer.give] = (b[offer.give] ?? 0) + offer.giveCount;
        final players = List<PlayerState>.of(s.players);
        players[s.active] = buyer.copyWith(stores: a);
        players[event.player] = seller.copyWith(stores: b);
        s = s.copyWith(players: players);
      }
      s = s.copyWith(clearTrade: true);
    } else if (event is EndTurn) {
      _require(s.phase == MatchPhase.actions, 'Roll and resolve Bandit first.');
      final next = (s.active + 1) % s.players.length;
      final newRound = s.round + (next == 0 ? 1 : 0);
      final pressure = s.reaverPressure + (next == 0 ? 1 : 0);
      s = s.copyWith(
        active: next,
        round: newRound,
        turnSerial: s.turnSerial + 1,
        reaverPressure: pressure,
        phase: next == 0 && pressure >= 3
            ? MatchPhase.invasion
            : MatchPhase.roll,
        clearDice: true,
        catchupUsed: next == 0 ? {} : s.catchupUsed,
        reliefUsed: next == 0 && (newRound - 1) % 3 == 0 ? {} : s.reliefUsed,
      );
    }
    if (winner(s) != null) s = s.copyWith(phase: MatchPhase.finished);
    return s.copyWith(events: [...s.events, event]);
  }
}
