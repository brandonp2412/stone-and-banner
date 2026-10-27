import 'package:flutter/material.dart';

import 'engine/match.dart';
import 'ui/match_screen.dart';

void main() => runApp(const StoneBannerApp());

enum Page { home, board, rules }

class StoneBannerApp extends StatefulWidget {
  const StoneBannerApp({super.key});
  @override
  State<StoneBannerApp> createState() => _StoneBannerAppState();
}

class _StoneBannerAppState extends State<StoneBannerApp> {
  Page page = Page.home;
  MatchState? match;
  bool handoff = false;
  int seats = 3;
  final seed = TextEditingController(text: '20261027');
  final names = [
    for (var i = 1; i <= 4; i++) TextEditingController(text: 'Player $i'),
  ];

  @override
  void dispose() {
    seed.dispose();
    for (final n in names) {
      n.dispose();
    }
    super.dispose();
  }

  void fail(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void start() {
    try {
      final s = MatchEngine.newGame([
        for (var i = 0; i < seats; i++) names[i].text.trim(),
      ], int.parse(seed.text));
      setState(() {
        match = s;
        page = Page.board;
        handoff = true;
      });
    } on FormatException {
      fail('Enter a numeric seed.');
    } on StateError catch (e) {
      fail(e.message);
    }
  }

  void dispatch(MatchEvent event) {
    try {
      final s = MatchEngine.apply(match!, event);
      setState(() {
        handoff =
            s.active != match!.active ||
            event is ProposeTrade ||
            event is RespondTrade;
        match = s;
      });
    } on StateError catch (e) {
      fail(e.message);
    }
  }

  Future<void> importMatch() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import replay'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Paste replay JSON',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Load'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null) return;
    try {
      final loaded = MatchEngine.importReplay(raw);
      setState(() {
        match = loaded;
        page = Page.board;
        handoff = true;
      });
    } on Object catch (e) {
      fail('Invalid replay: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = match;
    return MaterialApp(
      title: 'Stone & Banner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSans',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff806334)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffe7bf7b),
          brightness: Brightness.dark,
          surface: const Color(0xff192529),
        ),
      ),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) => PopScope(
          canPop: page == Page.home,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) setState(() => page = Page.home);
          },
          child: Scaffold(
            appBar: AppBar(
              centerTitle: true,
              title: const Text(
                'STONE & BANNER',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.7,
                ),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: page.index,
              onDestinationSelected: (n) =>
                  setState(() => page = Page.values[n]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hexagon_outlined),
                  label: 'Board',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  label: 'Rules',
                ),
              ],
            ),
            body: Stack(
              children: [
                switch (page) {
                  Page.home => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Text(
                            'Raise a town. Shape a realm.',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'An original offline pass-and-play strategy game. Claim villages, span the frontier and earn 15 Victory Points.',
                          ),
                          const SizedBox(height: 20),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'New local match',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 12),
                                  SegmentedButton<int>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 3,
                                        label: Text('3 players'),
                                      ),
                                      ButtonSegment(
                                        value: 4,
                                        label: Text('4 players'),
                                      ),
                                    ],
                                    selected: {seats},
                                    onSelectionChanged: (v) =>
                                        setState(() => seats = v.first),
                                  ),
                                  const SizedBox(height: 12),
                                  for (var i = 0; i < seats; i++) ...[
                                    TextField(
                                      controller: names[i],
                                      textCapitalization:
                                          TextCapitalization.words,
                                      decoration: InputDecoration(
                                        labelText: 'Seat ${i + 1}',
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  TextField(
                                    controller: seed,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'World seed',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton.icon(
                                    onPressed: start,
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Start match'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => setState(() => page = Page.rules),
                            icon: const Icon(Icons.menu_book_outlined),
                            label: const Text('Read the rules'),
                          ),
                          OutlinedButton.icon(
                            onPressed: importMatch,
                            icon: const Icon(Icons.history),
                            label: const Text('Import replay'),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '3–4 players · Local only · Reproducible seeds and events',
                          ),
                        ],
                      ),
                    ),
                  ),
                  Page.board =>
                    current == null
                        ? Center(
                            child: FilledButton(
                              onPressed: () => setState(() => page = Page.home),
                              child: const Text('Create a match'),
                            ),
                          )
                        : MatchView(state: current, onEvent: dispatch),
                  Page.rules => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Text(
                            'The founding rules',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 16),
                          const _Rule(
                            'Claim',
                            'Draft two Villages and adjoining roads per seat, in reverse order on the second pass. Settlements cannot be neighbours.',
                          ),
                          const _Rule(
                            'Roll',
                            'Matching numbers generate goods: Village one, Town two, Capital three. On a seven move the Bandit, blocking production on its hex.',
                          ),
                          const _Rule(
                            'Build',
                            'Road costs wood + brick. Village costs wood + brick + wheat + wool. Town costs 2 wheat + 3 ore. Capital costs 2 wood + 3 wheat + 3 ore in Stage 2.',
                          ),
                          const _Rule(
                            'Trade',
                            'Bank rate 4:1, or once per round at 3:1 if trailing by at least three points. Rival offers need consent.',
                          ),
                          const _Rule(
                            'Win',
                            'Reach 15 VP. Village = 1; Town = 2; Capital = 4. Longest unbroken road of five or more sides earns 2 VP.',
                          ),
                          const _Rule(
                            'Future stages',
                            'Paper, cloth, coin, Knights, Town Developments, Strategy Cards, Reaver Fleet and Invasion arrive later.',
                          ),
                          const Text(
                            'Every move is engine-validated and logged for deterministic replay.',
                          ),
                        ],
                      ),
                    ),
                  ),
                },
                if (page == Page.board && handoff && current != null)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Card(
                            margin: const EdgeInsets.all(24),
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.lock_outline, size: 42),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Pass the device',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    current.trade == null
                                        ? current.current.id
                                        : current
                                              .players[current.trade!.target]
                                              .id,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  Text(
                                    current.trade == null
                                        ? 'Your turn'
                                        : 'Private trade decision',
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton.icon(
                                    onPressed: () =>
                                        setState(() => handoff = false),
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text("I'm ready"),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule(this.name, this.description);
  final String name, description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(description),
      ],
    ),
  );
}
