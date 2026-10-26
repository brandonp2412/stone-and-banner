package nz.presley.stoneandbanner.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class GameEngineTest {
    @Test fun structuresHaveRequestedVictoryValues() {
        val player = PlayerState("Ada", buildings = listOf(Structure.VILLAGE, Structure.TOWN, Structure.CAPITAL))
        assertEquals(7, GameEngine.score(player))
    }

    @Test fun firstToFifteenWins() {
        val state = GameEngine.newGame(listOf("Ada", "Ben")).copy(
            players = listOf(PlayerState("Ada", charterPoints = 15), PlayerState("Ben"))
        )
        assertEquals("Ada", GameEngine.winner(state))
    }

    @Test fun seasonAndReactionsResetOnRoundBoundary() {
        var state = GameEngine.newGame(listOf("Ada", "Ben"))
        state = GameEngine.openReactionWindow(state, WindowType.INVASION)
        state = GameEngine.react(state, "Ben", Reaction.ESCORT)
        assertEquals(0, state.players[1].reactionTokens)
        assertThrows(IllegalArgumentException::class.java) {
            GameEngine.react(state, "Ben", Reaction.ESCORT)
        }
        state = GameEngine.closeReactionWindow(state)
        repeat(6) { state = GameEngine.advanceTurn(state) }
        assertEquals(4, state.round)
        assertEquals(Season.BLOOM, state.season)
        assertEquals(3, state.reaverPressure)
        assertEquals(1, state.players[1].reactionTokens)
    }

    @Test fun catchupTradeExchangesRealGoodsWithoutPointsAndOnlyOncePerRound() {
        var state = GameEngine.newGame(listOf("Ada", "Ben")).copy(
            activePlayerIndex = 1,
            players = listOf(
                PlayerState("Ada", buildings = listOf(Structure.CAPITAL)),
                PlayerState("Ben", stores = mapOf(Resource.WOOD to 7)),
            ),
        )
        assertEquals(3, GameEngine.bankTradeRate(state, "Ben"))
        state = GameEngine.bankTrade(state, "Ben", Resource.WOOD, Resource.WHEAT)
        assertEquals(4, state.players[1].stores[Resource.WOOD])
        assertEquals(1, state.players[1].stores[Resource.WHEAT])
        assertEquals(0, GameEngine.score(state.players[1]))
        assertEquals(4, GameEngine.bankTradeRate(state, "Ben"))
        state = GameEngine.bankTrade(state, "Ben", Resource.WOOD, Resource.ORE)
        assertEquals(0, state.players[1].stores[Resource.WOOD])
        assertEquals(1, state.players[1].stores[Resource.ORE])
        assertThrows(IllegalArgumentException::class.java) {
            GameEngine.bankTrade(state, "Ben", Resource.ORE, Resource.WHEAT)
        }
        assertThrows(IllegalArgumentException::class.java) {
            GameEngine.bankTrade(state, "Ben", Resource.WHEAT, Resource.PAPER)
        }
    }

    @Test fun turnOrderRejectsAdvanceDuringWindowAndBadPlayerIds() {
        val state = GameEngine.newGame(listOf("Ada", "Ben"))
        assertNull(GameEngine.winner(state))
        assertThrows(IllegalArgumentException::class.java) {
            GameEngine.newGame(listOf("Ada", "Ada"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            GameEngine.advanceTurn(GameEngine.openReactionWindow(state, WindowType.CARAVAN))
        }
    }
}
