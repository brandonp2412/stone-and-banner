package nz.presley.stoneandbanner.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BoardGeneratorTest {
    @Test fun deterministicSeedProducesSameBoardAndOtherSeedsDiffer() {
        assertEquals(BoardGenerator.generate(42), BoardGenerator.generate(42))
        assertNotEquals(BoardGenerator.generate(42).tiles, BoardGenerator.generate(43).tiles)
    }

    @Test fun terrainAndNumberDistributionIsValidAcrossSeeds() {
        for (seed in 0L..99L) {
            val board = BoardGenerator.generate(seed)
            assertEquals(19, board.tiles.size)
            assertEquals(19, board.tiles.map { it.position }.toSet().size)
            assertEquals(4, board.tiles.count { it.land == Land.WOODLAND })
            assertEquals(3, board.tiles.count { it.land == Land.CLAY_BEDS })
            assertEquals(4, board.tiles.count { it.land == Land.FIELDS })
            assertEquals(4, board.tiles.count { it.land == Land.MEADOWS })
            assertEquals(3, board.tiles.count { it.land == Land.RIDGES })
            assertEquals(1, board.tiles.count { it.land == Land.BARREN })
            assertEquals(18, board.tiles.count { it.productionNumber != null })
            assertTrue(board.tiles.none { a -> board.tiles.any { b ->
                a != b && a.position.touches(b.position) && board.tiles.any { c ->
                    c != a && c != b && c.position.touches(a.position) &&
                        c.position.touches(b.position) && a.land == b.land && b.land == c.land
                }
            } })
            val hot = board.tiles.filter { it.productionNumber == 6 || it.productionNumber == 8 }
            assertEquals(4, hot.size)
            assertTrue(hot.none { a -> hot.any { b -> a != b && a.position.touches(b.position) } })
        }
    }
}
