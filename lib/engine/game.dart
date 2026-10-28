import 'board.dart';
import 'cards.dart';

enum Structure {
  village(1),
  town(2),
  capital(4);

  const Structure(this.points);
  final int points;
}

enum StrategyDeck { innovation, commerce, governance }

enum Season { thaw, bloom, harvest, frost }

enum WindowType { caravan, invasion }

enum Reaction { offer, escort, blockade }

class PlayerState {
  PlayerState({
    required this.id,
    List<Structure> buildings = const [],
    Map<Resource, int> stores = const {},
    this.guardianHonour = 0,
    this.charterPoints = 0,
    this.reactionTokens = 1,
    Map<StrategyDeck, int> developments = const {},
    List<HeldCard> cards = const [],
  }) : cards = List.unmodifiable(cards),
       developments = Map.unmodifiable(developments),
       buildings = List.unmodifiable(buildings),
       stores = Map.unmodifiable(stores);
  final String id;
  final List<Structure> buildings;
  final Map<Resource, int> stores;
  final int guardianHonour, charterPoints, reactionTokens;
  final Map<StrategyDeck, int> developments;
  final List<HeldCard> cards;
  int level(StrategyDeck track) => developments[track] ?? 0;

  PlayerState copyWith({
    List<Structure>? buildings,
    Map<Resource, int>? stores,
    int? guardianHonour,
    int? charterPoints,
    int? reactionTokens,
    Map<StrategyDeck, int>? developments,
    List<HeldCard>? cards,
  }) => PlayerState(
    id: id,
    buildings: buildings ?? this.buildings,
    stores: stores ?? this.stores,
    guardianHonour: guardianHonour ?? this.guardianHonour,
    charterPoints: charterPoints ?? this.charterPoints,
    reactionTokens: reactionTokens ?? this.reactionTokens,
    developments: developments ?? this.developments,
    cards: cards ?? this.cards,
  );
}

class ReactionWindow {
  ReactionWindow({
    required this.type,
    required this.actingPlayerId,
    Map<String, Reaction> responses = const {},
  }) : responses = Map.unmodifiable(responses);
  final WindowType type;
  final String actingPlayerId;
  final Map<String, Reaction> responses;
  ReactionWindow copyWith({Map<String, Reaction>? responses}) => ReactionWindow(
    type: type,
    actingPlayerId: actingPlayerId,
    responses: responses ?? this.responses,
  );
}

class GameState {
  GameState({
    required List<PlayerState> players,
    this.activePlayerIndex = 0,
    this.round = 1,
    this.season = Season.thaw,
    this.reaverPressure = 0,
    Set<String> catchupTradeUsedBy = const {},
    this.reactionWindow,
  }) : players = List.unmodifiable(players),
       catchupTradeUsedBy = Set.unmodifiable(catchupTradeUsedBy);
  final List<PlayerState> players;
  final int activePlayerIndex, round, reaverPressure;
  final Season season;
  final Set<String> catchupTradeUsedBy;
  final ReactionWindow? reactionWindow;
  PlayerState get activePlayer => players[activePlayerIndex];

  GameState copyWith({
    List<PlayerState>? players,
    int? activePlayerIndex,
    int? round,
    Season? season,
    int? reaverPressure,
    Set<String>? catchupTradeUsedBy,
    ReactionWindow? reactionWindow,
    bool closeReactionWindow = false,
  }) => GameState(
    players: players ?? this.players,
    activePlayerIndex: activePlayerIndex ?? this.activePlayerIndex,
    round: round ?? this.round,
    season: season ?? this.season,
    reaverPressure: reaverPressure ?? this.reaverPressure,
    catchupTradeUsedBy: catchupTradeUsedBy ?? this.catchupTradeUsedBy,
    reactionWindow: closeReactionWindow
        ? null
        : reactionWindow ?? this.reactionWindow,
  );
}

class GameEngine {
  static const winningPoints = 15;
  static void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  static GameState newGame(List<String> ids) {
    require(
      ids.length >= 2 && ids.length <= 4,
      'Stone & Banner supports 2–4 local players.',
    );
    require(
      ids.every((id) => id.trim().isNotEmpty) &&
          ids.toSet().length == ids.length,
      'Invalid player names.',
    );
    return GameState(players: ids.map((id) => PlayerState(id: id)).toList());
  }

  static int score(PlayerState player) =>
      player.buildings.fold<int>(0, (sum, building) => sum + building.points) +
      player.guardianHonour +
      player.charterPoints;
  static String? winner(GameState state) {
    for (final player in state.players) {
      if (score(player) >= winningPoints) return player.id;
    }
    return null;
  }

  static GameState advanceTurn(GameState state) {
    require(state.reactionWindow == null, 'Resolve the reaction window first.');
    require(winner(state) == null, 'The game has ended.');
    final next = (state.activePlayerIndex + 1) % state.players.length;
    if (next != 0) return state.copyWith(activePlayerIndex: next);
    final round = state.round + 1;
    return state.copyWith(
      activePlayerIndex: 0,
      round: round,
      season: Season.values[((round - 1) ~/ 3) % Season.values.length],
      reaverPressure: state.reaverPressure + 1,
      catchupTradeUsedBy: {},
      players: [
        for (final player in state.players) player.copyWith(reactionTokens: 1),
      ],
    );
  }

  // A trailing player can trade 3:1 once per round; no free goods or VPs.
  static int bankTradeRate(GameState state, String playerId) {
    final player = state.players.singleWhere((player) => player.id == playerId);
    final best = state.players.map(score).reduce((a, b) => a > b ? a : b);
    return best - score(player) >= 3 &&
            !state.catchupTradeUsedBy.contains(playerId)
        ? 3
        : 4;
  }

  static GameState bankTrade(
    GameState state,
    String playerId,
    Resource spend,
    Resource receive,
  ) {
    require(
      state.activePlayer.id == playerId,
      'Only active players can bank trade.',
    );
    require(spend != receive, 'Choose different goods.');
    require(
      {
        Resource.wood,
        Resource.brick,
        Resource.wheat,
        Resource.wool,
        Resource.ore,
      }.contains(receive),
      'Only basic goods can be received.',
    );
    require(state.reactionWindow == null, 'Resolve the reaction window first.');
    final rate = bankTradeRate(state, playerId);
    final player = state.activePlayer;
    require((player.stores[spend] ?? 0) >= rate, 'Insufficient goods.');
    final stores = Map<Resource, int>.of(player.stores);
    stores[spend] = stores[spend]! - rate;
    stores[receive] = (stores[receive] ?? 0) + 1;
    final players = List<PlayerState>.of(state.players);
    players[state.activePlayerIndex] = player.copyWith(stores: stores);
    return state.copyWith(
      players: players,
      catchupTradeUsedBy: {
        ...state.catchupTradeUsedBy,
        if (rate == 3) playerId,
      },
    );
  }

  static GameState openReactionWindow(GameState state, WindowType type) {
    require(state.reactionWindow == null, 'Reaction window already open.');
    return state.copyWith(
      reactionWindow: ReactionWindow(
        type: type,
        actingPlayerId: state.activePlayer.id,
      ),
    );
  }

  static GameState react(GameState state, String playerId, Reaction reaction) {
    final window = state.reactionWindow;
    require(window != null, 'No reaction window.');
    require(playerId != window!.actingPlayerId, 'Acting player cannot react.');
    require(!window.responses.containsKey(playerId), 'Already responded.');
    final index = state.players.indexWhere((player) => player.id == playerId);
    require(index >= 0, 'Unknown player.');
    final player = state.players[index];
    require(player.reactionTokens > 0, 'No reaction tokens remaining.');
    require(
      (window.type == WindowType.caravan && reaction != Reaction.blockade) ||
          (window.type == WindowType.invasion && reaction != Reaction.offer),
      'Reaction not available in this window.',
    );
    final players = List<PlayerState>.of(state.players);
    players[index] = player.copyWith(reactionTokens: player.reactionTokens - 1);
    return state.copyWith(
      players: players,
      reactionWindow: window.copyWith(
        responses: {...window.responses, playerId: reaction},
      ),
    );
  }

  static GameState closeReactionWindow(GameState state) {
    require(state.reactionWindow != null, 'No reaction window.');
    return state.copyWith(closeReactionWindow: true);
  }
}
