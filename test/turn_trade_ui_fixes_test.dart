import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/advanced.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/dice_roll.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('bot offer permits a counteroffer', (
    tester,
  ) async {
    var state = tableWithSupplies().copyWith(active: 1);
    final players = state.players.toList();
    players[1] = players[1].copyWith(
      stores: {...players[1].stores, Resource.wood: 2},
    );
    state = state.copyWith(players: players);
    state = MatchEngine.apply(
      state,
      const ProposeTrade(0, Resource.wood, 1, Resource.wool, 1),
    );
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchView(
            state: state,
            visibleSeat: 0,
            computerSeats: const {1},
            onEvent: events.add,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('bot-trade-dialog')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byType(SlideTransition), findsWidgets);
    await tester.pumpAndSettle();
    final create = tester.widget<FilledButton>(
      find.byKey(const ValueKey('create-player-offer')),
    );
    expect(create.onPressed, isNull);
    final offer = state.offers.single;
    final counter = tester.widget<OutlinedButton>(
      find.byKey(ValueKey('counter-offer-${offer.id}')),
    );
    expect(counter.onPressed, isNotNull);
    await tester.tap(find.byKey(ValueKey('decline-offer-${offer.id}')));
    await tester.pumpAndSettle();
    expect(events.single, isA<RespondTrade>());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('blocking dialog does not pause the local turn clock', (tester) async {
    var state = tableWithSupplies();
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => MatchView(
              state: state,
              onEvent: (event) {
                events.add(event);
                refresh(() => state = MatchEngine.apply(state, event));
              },
            ),
          ),
        ),
      ),
    );

    final matchContext = tester.element(find.byType(MatchView));
    showDialog<void>(
      context: matchContext,
      builder: (context) => AlertDialog(
        title: const Text('Take your time'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close dialog'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 95));
    expect(events.single, isA<EndTurn>());
    await tester.pumpAndSettle();
    expect(find.text('Close dialog'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expired action turn advances once and resets the clock', (
    tester,
  ) async {
    var state = tableWithSupplies();
    final initialSeat = state.active;
    final events = <MatchEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => MatchView(
              state: state,
              onEvent: (event) {
                events.add(event);
                refresh(() => state = MatchEngine.apply(state, event));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 89));
    expect(events, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(events.single, isA<EndTurn>());
    expect(state.active, (initialSeat + 1) % state.players.length);
    await tester.pump(const Duration(seconds: 1));
    expect(events, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expired roll progresses through to the next player', (
    tester,
  ) async {
    var state = tableWithSupplies().copyWith(phase: MatchPhase.roll);
    final initialSeat = state.active;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, refresh) => MatchView(
              state: state,
              onEvent: (event) =>
                  refresh(() => state = MatchEngine.apply(state, event)),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 90));
    for (var i = 0; i < 5 && state.active == initialSeat; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(state.active, (initialSeat + 1) % state.players.length);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'human interception waits while computer interception stays hidden',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = tableWithSupplies();
      final s = base.copyWith(
        tactical: TacticalWindow(77, TacticalKind.bandit, 1, [
          0,
        ], bandit: const MoveBandit(0, victim: 0)),
        knights: {5: const KnightPiece(0, KnightRank.sentinel, true, -1)},
      );
      var observing = false;
      late StateSetter refresh;
      final events = <MatchEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                refresh = setState;
                return MatchView(
                  state: s,
                  observing: observing,
                  onEvent: events.add,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Intercept with Knight'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Intercept with Knight'), findsOneWidget);
      expect(events, isEmpty);
      refresh(() => observing = true);
      await tester.pumpAndSettle();
      expect(find.text('Intercept with Knight'), findsNothing);
      expect(find.text('Watch the realm grow.'), findsNothing);
    },
  );

  testWidgets(
    'roll animation appears on the board and clears after completion',
    (tester) async {
      await (FontLoader(
        'NotoSans',
      )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = tableWithSupplies();
      var s = base;
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'NotoSans', brightness: Brightness.dark),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                refresh = setState;
                return MatchView(state: s, observing: true, onEvent: (_) {});
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      refresh(
        () => s = base.copyWith(
          events: [...base.events, const RollDice(2, 6)],
          dice: 8,
        ),
      );
      await tester.pump();
      expect(find.byType(DiceRoll), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.pump(const Duration(milliseconds: 720));
      await expectLater(
        find.byKey(const ValueKey('realm-map')),
        matchesGoldenFile('goldens/activated_numbers.png'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DiceRoll), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
