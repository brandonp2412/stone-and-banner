package nz.presley.stoneandbanner.engine

import kotlin.math.abs
import kotlin.random.Random

data class HexCoord(val q: Int, val r: Int) {
    fun touches(other: HexCoord): Boolean {
        val dq = q - other.q
        val dr = r - other.r
        return (abs(dq) + abs(dr) + abs(dq + dr)) / 2 == 1
    }
}

enum class Land(val produces: Resource?) {
    WOODLAND(Resource.WOOD),
    CLAY_BEDS(Resource.BRICK),
    FIELDS(Resource.WHEAT),
    MEADOWS(Resource.WOOL),
    RIDGES(Resource.ORE),
    BARREN(null),
}

data class HexTile(val position: HexCoord, val land: Land, val productionNumber: Int?)
data class Board(val seed: Long, val tiles: List<HexTile>)

object BoardGenerator {
    private val terrainBag = listOf(
        *Array(4) { Land.WOODLAND },
        *Array(3) { Land.CLAY_BEDS },
        *Array(4) { Land.FIELDS },
        *Array(4) { Land.MEADOWS },
        *Array(3) { Land.RIDGES },
        Land.BARREN,
    )
    private val numberBag = listOf(2, 12) +
        listOf(3, 4, 5, 6, 8, 9, 10, 11).flatMap { listOf(it, it) }
    private val coordinates = buildList {
        for (q in -2..2) for (r in -2..2) {
            if (abs(q + r) <= 2) add(HexCoord(q, r))
        }
    }

    // Stable setup from an explicit seed; the resulting layout is also saved in replay.
    fun generate(seed: Long): Board {
        val random = Random(seed)
        repeat(10_000) {
            val lands = terrainBag.shuffled(random)
            val tilesWithoutNumbers = coordinates.zip(lands)
            val hasThreeMatchingAtVertex = tilesWithoutNumbers.indices.any { i ->
                tilesWithoutNumbers.indices.any { j ->
                    j > i && coordinates[i].touches(coordinates[j]) &&
                        tilesWithoutNumbers.indices.any { k ->
                            k > j && coordinates[i].touches(coordinates[k]) &&
                                coordinates[j].touches(coordinates[k]) &&
                                lands[i] == lands[j] && lands[j] == lands[k]
                        }
                }
            }
            if (hasThreeMatchingAtVertex) return@repeat
            val numbers = numberBag.shuffled(random).iterator()
            val board = Board(seed, coordinates.mapIndexed { index, position ->
                val land = lands[index]
                HexTile(position, land, if (land == Land.BARREN) null else numbers.next())
            })
            val hot = board.tiles.filter { it.productionNumber == 6 || it.productionNumber == 8 }
            if (hot.any { a -> hot.any { b -> a != b && a.position.touches(b.position) } }) {
                return@repeat
            }
            return board
        }
        error("Unable to generate a balanced board with seed $seed")
    }
}
