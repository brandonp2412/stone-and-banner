package nz.presley.stoneandbanner.engine

enum class Resource { WOOD, BRICK, WHEAT, WOOL, ORE, PAPER, CLOTH, COIN }
enum class Structure(val points: Int) { VILLAGE(1), TOWN(2), CAPITAL(4) }
enum class StrategyDeck { INNOVATION, COMMERCE, GOVERNANCE }
enum class Season { THAW, BLOOM, HARVEST, FROST }
enum class WindowType { CARAVAN, INVASION }
enum class Reaction { OFFER, ESCORT, BLOCKADE }

data class PlayerState(
    val id: String,
    val buildings: List<Structure> = emptyList(),
    val stores: Map<Resource, Int> = emptyMap(),
    val guardianHonour: Int = 0,
    val charterPoints: Int = 0,
    val reactionTokens: Int = 1,
)

data class ReactionWindow(
    val type: WindowType,
    val actingPlayerId: String,
    val responses: Map<String, Reaction> = emptyMap(),
)

data class GameState(
    val players: List<PlayerState>,
    val activePlayerIndex: Int = 0,
    val round: Int = 1,
    val season: Season = Season.THAW,
    val reaverPressure: Int = 0,
    val catchupTradeUsedBy: Set<String> = emptySet(),
    val reactionWindow: ReactionWindow? = null,
) {
    val activePlayer: PlayerState get() = players[activePlayerIndex]
}

object GameEngine {
    const val WINNING_POINTS = 15

    fun newGame(playerIds: List<String>): GameState {
        require(playerIds.size in 2..4) { "Stone & Banner supports 2–4 local players." }
        require(playerIds.all { it.isNotBlank() } && playerIds.distinct().size == playerIds.size)
        return GameState(players = playerIds.map(::PlayerState))
    }

    fun score(player: PlayerState): Int =
        player.buildings.sumOf { it.points } + player.guardianHonour + player.charterPoints

    fun winner(state: GameState): String? =
        state.players.firstOrNull { score(it) >= WINNING_POINTS }?.id

    fun advanceTurn(state: GameState): GameState {
        require(state.reactionWindow == null) { "Resolve the reaction window first." }
        require(winner(state) == null) { "The game has ended." }
        val next = (state.activePlayerIndex + 1) % state.players.size
        if (next != 0) return state.copy(activePlayerIndex = next)
        val newRound = state.round + 1
        return state.copy(
            activePlayerIndex = 0,
            round = newRound,
            season = Season.entries[((newRound - 1) / 3) % Season.entries.size],
            reaverPressure = state.reaverPressure + 1,
            catchupTradeUsedBy = emptySet(),
            players = state.players.map { it.copy(reactionTokens = 1) },
        )
    }

    // One optional 3:1 bank trade each round for players at least 3 VP behind.
    // No resource or VP is ever minted: four ordinary goods reduce to three paid goods.
    fun bankTradeRate(state: GameState, playerId: String): Int {
        val player = state.players.single { it.id == playerId }
        val gap = state.players.maxOf(::score) - score(player)
        return if (gap >= 3 && playerId !in state.catchupTradeUsedBy) 3 else 4
    }

    fun bankTrade(
        state: GameState,
        playerId: String,
        spend: Resource,
        receive: Resource,
    ): GameState {
        require(state.activePlayer.id == playerId) { "Only the active player may bank trade." }
        require(spend != receive) { "Choose different goods." }
        require(receive in setOf(Resource.WOOD, Resource.BRICK, Resource.WHEAT, Resource.WOOL, Resource.ORE)) {
            "Bank trades supply basic goods only."
        }
        require(state.reactionWindow == null)
        val rate = bankTradeRate(state, playerId)
        val player = state.activePlayer
        require(player.stores.getOrDefault(spend, 0) >= rate) { "Insufficient goods." }
        val updatedStores = player.stores.toMutableMap().apply {
            this[spend] = getValue(spend) - rate
            this[receive] = getOrDefault(receive, 0) + 1
        }
        val updatedPlayers = state.players.toMutableList().apply {
            set(state.activePlayerIndex, player.copy(stores = updatedStores.toMap()))
        }
        return state.copy(
            players = updatedPlayers,
            catchupTradeUsedBy = if (rate == 3) state.catchupTradeUsedBy + playerId
            else state.catchupTradeUsedBy,
        )
    }

    fun openReactionWindow(state: GameState, type: WindowType): GameState {
        require(state.reactionWindow == null)
        return state.copy(reactionWindow = ReactionWindow(type, state.activePlayer.id))
    }

    fun react(state: GameState, playerId: String, reaction: Reaction): GameState {
        val window = requireNotNull(state.reactionWindow)
        require(playerId != window.actingPlayerId) { "Acting player cannot react." }
        require(playerId !in window.responses) { "Already responded." }
        val index = state.players.indexOfFirst { it.id == playerId }
        require(index >= 0)
        val player = state.players[index]
        require(player.reactionTokens > 0) { "No reaction tokens remaining." }
        require(
            (window.type == WindowType.CARAVAN && reaction != Reaction.BLOCKADE) ||
                (window.type == WindowType.INVASION && reaction != Reaction.OFFER)
        ) { "Reaction not available in this window." }
        return state.copy(
            players = state.players.toMutableList().apply {
                set(index, player.copy(reactionTokens = player.reactionTokens - 1))
            },
            reactionWindow = window.copy(responses = window.responses + (playerId to reaction)),
        )
    }

    fun closeReactionWindow(state: GameState): GameState {
        require(state.reactionWindow != null)
        return state.copy(reactionWindow = null)
    }
}
