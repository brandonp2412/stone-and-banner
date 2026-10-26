package nz.presley.stoneandbanner

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import nz.presley.stoneandbanner.engine.BoardGenerator
import nz.presley.stoneandbanner.engine.GameEngine
import nz.presley.stoneandbanner.engine.Season
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { StoneBannerApp() }
    }
}

private enum class Page(val title: String, val symbol: String) {
    HOME("Home", "⌂"), BOARD("Board", "⬡"), RULES("Rules", "≡")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StoneBannerApp() {
    val isDark = (LocalContext.current.resources.configuration.uiMode and 0x30) == 0x20
    val palette = if (isDark) darkColorScheme(
        primary = Color(0xFFE6BD7D), secondary = Color(0xFF9FC9B0),
        background = Color(0xFF171F21), surface = Color(0xFF212C2D),
    ) else lightColorScheme(
        primary = Color(0xFF675020), secondary = Color(0xFF486D56),
        background = Color(0xFFF7F3E9), surface = Color(0xFFFFFCF5),
    )
    var page by remember { mutableStateOf(Page.HOME) }
    var game by remember { mutableStateOf(GameEngine.newGame(listOf("Player 1", "Player 2"))) }
    BackHandler(page != Page.HOME) { page = Page.HOME }

    MaterialTheme(colorScheme = palette) {
        Scaffold(
            topBar = { CenterAlignedTopAppBar(title = { Text("STONE & BANNER") }) },
            bottomBar = {
                NavigationBar {
                    Page.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = page == tab,
                            onClick = { page = tab },
                            icon = { Text(tab.symbol) },
                            label = { Text(tab.title) },
                        )
                    }
                }
            },
        ) { insets ->
            when (page) {
                Page.HOME -> HomeScreen(insets, onBoard = { page = Page.BOARD },
                    onRules = { page = Page.RULES })
                Page.BOARD -> BoardScreen(insets, game.round, game.activePlayer.id, game.season) {
                    game = GameEngine.advanceTurn(game)
                }
                Page.RULES -> RulesScreen(insets)
            }
        }
    }
}

@Composable
private fun HomeScreen(insets: PaddingValues, onBoard: () -> Unit, onRules: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(insets).verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Raise a town. Shape a realm.", style = MaterialTheme.typography.headlineLarge)
        Text(
            "A new turn-based strategy world built around changing markets, common defence, " +
                "and decisions that matter even when it isn't your turn.",
            style = MaterialTheme.typography.bodyLarge,
        )
        Card {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Stage 1 · Founding build", style = MaterialTheme.typography.titleMedium)
                Text("Explore the board prototype, turn order and draft rules. Full local play comes next.")
                Button(onClick = onBoard, modifier = Modifier.fillMaxWidth()) { Text("Open board preview") }
                OutlinedButton(onClick = onRules, modifier = Modifier.fillMaxWidth()) { Text("Read rule primer") }
            }
        }
        Text("2–4 players planned · Local pass-and-play first · Offline by design")
    }
}

@Composable
private fun BoardScreen(
    insets: PaddingValues,
    round: Int,
    activePlayer: String,
    season: Season,
    onNextTurn: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(insets).verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("The frontier", style = MaterialTheme.typography.headlineMedium)
        Card {
            Column(Modifier.fillMaxWidth().padding(12.dp)) {
                Text("Procedural layout preview · no moves yet", style = MaterialTheme.typography.labelMedium)
                HexBoard(Modifier.fillMaxWidth().aspectRatio(1.05f))
            }
        }
        Text("Round " + round + " · " + season.name.lowercase().replaceFirstChar(Char::uppercaseChar),
            style = MaterialTheme.typography.titleMedium)
        Text("Turn: " + activePlayer)
        Button(onClick = onNextTurn, modifier = Modifier.fillMaxWidth()) {
            Text("Advance preview turn")
        }
        Text("Develop towns, build roads, prepare knights and answer rival actions. " +
            "Board placement and rules enforcement arrive in Stage 2.")
    }
}

private val board = BoardGenerator.generate(20261027L).tiles
private val terrain = listOf(
    Color(0xFF6D9874), Color(0xFFC17F63), Color(0xFFDBC58D),
    Color(0xFF97B8A5), Color(0xFF94A0A5),
)

@Composable
private fun HexBoard(modifier: Modifier = Modifier) {
    Surface(modifier, shape = MaterialTheme.shapes.large, color = Color(0xFF283F48)) {
        Canvas(Modifier.fillMaxSize().padding(12.dp)) {
            val hexSize = size.minDimension / 6.0f
            val center = Offset(size.width / 2f, size.height / 2f)
            val root3 = sqrt(3f)
            board.forEach { cell ->
                val x = center.x + root3 * hexSize * (cell.position.q + cell.position.r / 2f)
                val y = center.y + 1.5f * hexSize * cell.position.r
                val path = Path().apply {
                    for (i in 0..5) {
                        val angle = (i * 60.0 - 30.0) * PI / 180
                        val px = x + hexSize * cos(angle).toFloat()
                        val py = y + hexSize * sin(angle).toFloat()
                        if (i == 0) moveTo(px, py) else lineTo(px, py)
                    }
                    close()
                }
                drawPath(path, terrain[cell.land.ordinal])
                drawPath(path, Color(0xFF283F48), style = Stroke(width = 3f))
                drawCircle(Color(0x44FFFFFF), radius = hexSize * 0.12f, center = Offset(x, y))
            }
        }
    }
}

@Composable
private fun RulesScreen(insets: PaddingValues) {
    Column(
        Modifier.fillMaxSize().padding(insets).verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("The founding rules", style = MaterialTheme.typography.headlineMedium)
        Rule("Build", "Village 1 VP · Town 2 VP · Capital 4 VP total. Reach 15 Victory Points.")
        Rule("Trade", "Wood, brick, wheat, wool and ore support construction. " +
            "Paper, cloth and coin fund advanced developments.")
        Rule("Develop", "Innovation, Commerce and Governance are three independent strategy paths.")
        Rule("Respond", "Offer, Escort and Blockade can change a rival's move " +
            "in a short, shared reaction window.")
        Rule("Recover", "A trailing player can make one 3:1 bank exchange per round " +
            "when at least three points behind—never a free Victory Point.")
        Text("This is a primer; the full original ruleset lives in docs/RULES.md.")
    }
}

@Composable
private fun Rule(heading: String, body: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(heading, style = MaterialTheme.typography.titleMedium)
        Text(body, style = MaterialTheme.typography.bodyMedium)
    }
}
