import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'engine/board.dart';
import 'engine/game.dart';

void main() => runApp(const StoneBannerApp());

enum _Page { home, board, rules }

class StoneBannerApp extends StatefulWidget {
  const StoneBannerApp({super.key});
  @override
  State<StoneBannerApp> createState() => _StoneBannerAppState();
}

class _StoneBannerAppState extends State<StoneBannerApp> {
  _Page page = _Page.home;
  GameState game = GameEngine.newGame(['Player 1', 'Player 2']);
  final Board board = BoardGenerator.generate(20261027);

  @override
  Widget build(BuildContext context) {
    final light = ColorScheme.fromSeed(seedColor: const Color(0xff806334));
    final dark = ColorScheme.fromSeed(
      seedColor: const Color(0xffe7bf7b),
      brightness: Brightness.dark,
      surface: const Color(0xff192529),
    );
    return MaterialApp(
      title: 'Stone & Banner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSans',
        colorScheme: light,
        scaffoldBackgroundColor: const Color(0xfff7f3e9),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSans',
        colorScheme: dark,
        scaffoldBackgroundColor: const Color(0xff10191d),
      ),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) => PopScope(
          canPop: page == _Page.home,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && page != _Page.home) {
              setState(() => page = _Page.home);
            }
          },
          child: Scaffold(
            appBar: AppBar(
              centerTitle: true,
              title: const Text(
                'STONE & BANNER',
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: page.index,
              onDestinationSelected: (index) =>
                  setState(() => page = _Page.values[index]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hexagon_outlined),
                  selectedIcon: Icon(Icons.hexagon),
                  label: 'Board',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: 'Rules',
                ),
              ],
            ),
            body: switch (page) {
              _Page.home => _HomeScreen(
                onBoard: () => setState(() => page = _Page.board),
                onRules: () => setState(() => page = _Page.rules),
              ),
              _Page.board => _BoardScreen(
                board: board,
                game: game,
                onNextTurn: () =>
                    setState(() => game = GameEngine.advanceTurn(game)),
              ),
              _Page.rules => const _RulesScreen(),
            },
          ),
        ),
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.onBoard, required this.onRules});
  final VoidCallback onBoard, onRules;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Raise a town. Shape a realm.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 14),
      Text(
        'A turn-based strategy world of shifting markets, common defence and decisions that matter even when it isn’t your turn.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Stage 1 · Founding build',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Explore the board prototype, turn order and draft rules. Full local play comes next.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onBoard,
                icon: const Icon(Icons.hexagon_outlined),
                label: const Text('Open board preview'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onRules,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Read rule primer'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        '2–4 players planned · Local pass-and-play first · Offline by design',
      ),
    ],
  );
}

class _BoardScreen extends StatelessWidget {
  const _BoardScreen({
    required this.board,
    required this.game,
    required this.onNextTurn,
  });
  final Board board;
  final GameState game;
  final VoidCallback onNextTurn;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('The frontier', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Procedural layout preview · no moves yet',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 1.05,
                child: Semantics(
                  label: 'Nineteen hex terrain board preview',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CustomPaint(
                      painter: _BoardPainter(board),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Round ${game.round} · ${game.season.name[0].toUpperCase()}${game.season.name.substring(1)}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        'Turn: ${game.activePlayer.id}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: onNextTurn,
        child: const Text('Advance preview turn'),
      ),
      const SizedBox(height: 10),
      const Text(
        'Develop towns, build roads, prepare knights and respond to rival actions. Board placement and costs arrive in Stage 2.',
      ),
    ],
  );
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter(this.board);
  final Board board;
  static const terrain = [
    Color(0xff6d9874),
    Color(0xffc17f63),
    Color(0xffdbc58d),
    Color(0xff97b8a5),
    Color(0xff94a0a5),
    Color(0xff756b5c),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff283f48), BlendMode.src);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 9.66, size.height / 9.0);
    for (final tile in board.tiles) {
      final x =
          center.dx +
          math.sqrt(3) * radius * (tile.position.q + tile.position.r / 2);
      final y = center.dy + 1.5 * radius * tile.position.r;
      final path = Path();
      for (var index = 0; index < 6; index++) {
        final angle = (index * 60 - 30) * math.pi / 180;
        final px = x + radius * math.cos(angle),
            py = y + radius * math.sin(angle);
        if (index == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..color = terrain[tile.land.index]);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff283f48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      if (tile.productionNumber case final int number) {
        canvas.drawCircle(
          Offset(x, y),
          radius * .32,
          Paint()..color = const Color(0xfff7f0da),
        );
        final text = TextPainter(
          text: TextSpan(
            text: '$number',
            style: TextStyle(
              color: number == 6 || number == 8
                  ? const Color(0xffad332f)
                  : const Color(0xff263338),
              fontFamily: 'NotoSans',
              fontSize: radius * .31,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(x - text.width / 2, y - text.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      !identical(board, oldDelegate.board);
}

class _RulesScreen extends StatelessWidget {
  const _RulesScreen();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'The founding rules',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 18),
      const _Rule(
        'Build',
        'Village 1 VP · Town 2 VP · Capital 4 VP total. Reach 15 Victory Points.',
      ),
      const _Rule(
        'Trade',
        'Wood, brick, wheat, wool and ore support construction. Paper, cloth and coin fund advanced developments.',
      ),
      const _Rule(
        'Develop',
        'Innovation, Commerce and Governance are three independent strategy paths.',
      ),
      const _Rule(
        'Respond',
        'Offer, Escort and Blockade can change a rival’s move during a short shared reaction window.',
      ),
      const _Rule(
        'Recover',
        'A trailing player may make one 3:1 bank exchange per round when three or more points behind—never free Victory Points.',
      ),
      const SizedBox(height: 16),
      const Text('This is a primer. The full rules live in docs/RULES.md.'),
    ],
  );
}

class _Rule extends StatelessWidget {
  const _Rule(this.heading, this.body);
  final String heading, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(body),
      ],
    ),
  );
}
