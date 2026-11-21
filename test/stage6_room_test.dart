import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/ai_turn_coordinator.dart';
import 'package:stone_and_banner/engine/board.dart';
import 'package:stone_and_banner/engine/cards.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_host.dart';
import 'package:stone_and_banner/network/room_protocol.dart';

void main() {
  HostedRoom openRoom([int capacity = 3]) {
    final room = LanRoomRegistry().create(capacity, 42, 'Ada');
    room.join('Ben');
    room.join('Cora');
    if (capacity == 4) room.join('Dee');
    room.start(0);
    return room;
  }

  test('lobby occupancy, identity and creator-only start', () {
    final registry = LanRoomRegistry();
    final room = registry.create(4, 12, 'Ada');
    expect(room.seats.first.token.length, 64);
    expect(room.seatFor(room.seats.first.token), 0);
    expect(room.seatFor('untrusted'), -1);
    expect(() => room.start(1), throwsStateError);
    expect(() => room.start(0), throwsStateError);
    expect(() => room.join('ada'), throwsStateError);
    room.join('Ben');
    room.join('Cora');
    room.join('Dee');
    room.start(0);
    expect(room.state!.players.length, 4);
    expect(() => room.join('Eve'), throwsStateError);
    expect(registry.find(room.id), same(room));
  });

  test('authoritative legality, stale version, and replay-safe dedupe', () {
    final room = openRoom();
    final village = PlaceVillage(MatchEngine.legalVertices(room.state!).first);
    final command = village.toJson();
    final first = room.move(0, 'req-1', 0, command);
    expect(first['ok'], true);
    expect(room.version, 1);
    expect(room.move(0, 'req-1', 0, command), first);
    expect(room.version, 1);
    expect(room.move(0, 'req-1', 0, const PlaceRoad(0).toJson())['ok'], false);
    expect(room.move(1, 'malicious', 1, command)['ok'], false);
    expect(room.move(0, 'stale', 0, command)['ok'], false);
    expect(
      room.move(
        0,
        'fake-timeout',
        1,
        const TimeoutTactical(0, 0).toJson(),
      )['ok'],
      false,
    );
    final edge = PlaceRoad(MatchEngine.legalEdges(room.state!).first);
    expect(room.move(0, 'req-2', 1, edge.toJson())['ok'], true);
    expect(room.state!.active, 1);
    expect(room.version, 2);
    final publicState = RoomProtocol.readView(
      RoomProtocol.view(room.state!, 1),
    );
    expect(
      MatchEngine.score(publicState, 0),
      MatchEngine.score(room.state!, 0),
    );
    expect(
      MatchEngine.snapshot(room.replayOnHost()),
      MatchEngine.snapshot(room.state!),
    );
    expect(room.replayOnHost().board.seed, 42);
    expect(room.replayOnHost().seed, room.secretSeed);
    expect(room.historyAfter(1).length, 1);
    expect(room.historyAfter(2), isEmpty);
  });

  test(
    'private seat view never sends deck seed, replay or rival goods/cards',
    () {
      final room = openRoom();
      final state = room.state!;
      final original = state.players.toList();
      final cards = [const HeldCard(StrategyDeck.governance, 0)];
      final players = original.toList();
      players[0] = original[0].copyWith(
        stores: {Resource.wool: 4},
        cards: cards,
      );
      players[1] = original[1].copyWith(
        stores: {Resource.ore: 5},
        cards: cards,
      );
      room.state = state.copyWith(players: players);
      final ada = RoomProtocol.view(room.state!, 0);
      final ben = RoomProtocol.view(room.state!, 1);
      expect(ada['seed'], 0);
      expect(ada['boardTiles'], hasLength(19));
      expect(ada['events'], isEmpty);
      expect(ada['drawPiles'], isEmpty);
      expect(ada['discardPiles'], isEmpty);
      final p0 = (ada['players'] as List)[0] as Map;
      final p1 = (ada['players'] as List)[1] as Map;
      expect(p0['cards'], isNotEmpty);
      expect(p1['cards'], isEmpty);
      expect((p1['resources'] as List).every((v) => v == 0), true);
      expect(((ben['players'] as List)[0] as Map)['cards'], isEmpty);
      final decoded = RoomProtocol.readView(ada);
      expect(decoded.players[0].stores[Resource.wool], 4);
      expect(decoded.players[1].stores[Resource.ore], 0);
      expect(decoded.players[1].cards, isEmpty);
      expect(decoded.board.tiles, room.state!.board.tiles);
      expect(decoded.topology.edges.length, state.topology.edges.length);
    },
  );

  test('standing offers and duplicate acceptance cannot mint goods', () {
    final room = openRoom();
    final start = room.state!;
    final players = start.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wood: 3});
    players[1] = players[1].copyWith(stores: {Resource.wool: 2});
    room.state = start.copyWith(
      phase: MatchPhase.actions,
      players: players,
      bank: {...start.bank, Resource.wood: 16, Resource.wool: 17},
    );
    final offer = ProposeTrade(1, Resource.wood, 2, Resource.wool, 1);
    expect(room.move(0, 'offer-1', 0, offer.toJson())['ok'], true);
    expect(room.state!.offers.single.giveCount, 2);
    expect(room.state!.players[0].stores[Resource.wood], 3);
    expect(room.move(0, 'offer-1', 0, offer.toJson())['ok'], true);
    expect(room.state!.offers.length, 1);
    final old = room.state!.events.length;
    room.state = room.state!.copyWith(active: 1);
    final accept = RespondTrade(1, true, offerId: room.state!.offers.single.id);
    expect(room.move(1, 'accept-1', old, accept.toJson())['ok'], true);
    expect(room.move(1, 'accept-1', old, accept.toJson())['ok'], true);
    expect(room.state!.offers, isEmpty);
    expect(room.state!.players[0].stores[Resource.wool], 1);
    expect(room.state!.players[1].stores[Resource.wood], 2);
    expect(room.state!.bank[Resource.wood], 16);
    expect(room.state!.bank[Resource.wool], 17);
  });

  test('server-only tactical deadline passes and records exactly once', () {
    final room = openRoom();
    final state = room.state!;
    room.state = state.copyWith(
      phase: MatchPhase.invasion,
      tactical: TacticalWindow(90, TacticalKind.invasion, 0, [1]),
    );
    final before = room.version;
    expect(
      room.move(1, 'fake', before, const TimeoutTactical(90, 1).toJson())['ok'],
      false,
    );
    expect(room.timeout(90, 0), false);
    expect(room.timeout(90, 1), true);
    expect(room.timeout(90, 1), false);
    expect(room.version, before + 1);
    expect(room.state!.tactical, isNull);
    expect(room.historyAfter(before).single['kind'], 'tacticalTimeout');
  });

  test('host chooses secret dice and bounds idle setup/turns', () {
    final room = openRoom();
    expect(room.advanceIdle(1), false);
    expect(room.advanceIdle(0), true);
    expect(room.state!.phase, MatchPhase.setupRoad);
    expect(room.advanceIdle(1), true);
    expect(room.version, 2);
    room.state = room.state!.copyWith(phase: MatchPhase.roll, active: 0);
    final roll = room.move(0, 'roll', 2, const RollDice(0, 0).toJson());
    expect(roll['ok'], true);
    expect(room.state!.dice, inInclusiveRange(2, 12));
    expect(room.state!.events.last.toJson()['first'], isNot(0));
  });

  test('multiplayer broadcasts can be declined, accepted and countered', () {
    final room = openRoom();
    final original = room.state!;
    final players = original.players.toList();
    players[0] = players[0].copyWith(stores: {Resource.wood: 2});
    players[1] = players[1].copyWith(stores: {Resource.wheat: 2});
    players[2] = players[2].copyWith(stores: {Resource.wheat: 2});
    room.state = original.copyWith(phase: MatchPhase.actions, players: players);
    const broadcast = ProposeTrade(-1, Resource.wood, 1, Resource.wheat, 1);
    expect(room.move(0, 'everyone', 0, broadcast.toJson())['ok'], true);
    final id = room.state!.offers.single.id;
    expect(
      room.move(
        1,
        'decline',
        1,
        RespondTrade(1, false, offerId: id).toJson(),
      )['ok'],
      true,
    );
    expect(room.state!.offers.single.declinedBy, {1});
    expect(
      room.move(
        2,
        'accept',
        2,
        RespondTrade(2, true, offerId: id).toJson(),
      )['ok'],
      true,
    );
    expect(room.state!.offers, isEmpty);
    expect(room.state!.players[0].stores[Resource.wheat], 1);
    expect(room.state!.players[2].stores[Resource.wood], 1);
    expect(
      room.move(
        2,
        'duplicate',
        3,
        RespondTrade(2, true, offerId: id).toJson(),
      )['ok'],
      false,
    );

    room.state = original.copyWith(phase: MatchPhase.actions, players: players);
    expect(room.move(0, 'again', 0, broadcast.toJson())['ok'], true);
    final newId = room.state!.offers.single.id;
    final counter = ProposeTrade(
      0,
      Resource.wheat,
      1,
      Resource.wood,
      1,
      counterOf: newId,
      counterActor: 1,
    );
    expect(room.move(1, 'counter', 1, counter.toJson())['ok'], true);
    expect(room.state!.offers.single.proposer, 1);
    expect(room.state!.offers.single.target, 0);
  });

  test(
    'multiplayer host AI answers broadcast trades without pausing',
    () async {
      final room = openRoom();
      final initial = room.state!;
      final players = initial.players.toList();
      players[0] = players[0].copyWith(stores: {Resource.wood: 2});
      players[1] = players[1].copyWith(stores: {Resource.wheat: 2});
      players[2] = players[2].copyWith(stores: {Resource.wheat: 2});
      room.state = initial.copyWith(
        phase: MatchPhase.actions,
        players: players,
      );
      expect(
        room.move(
          0,
          'offer',
          room.version,
          const ProposeTrade(-1, Resource.wood, 1, Resource.wheat, 1).toJson(),
        )['ok'],
        true,
      );

      Object? failure;
      bool isBot(int seat) => seat == 1 || seat == 2;
      final ai = AiTurnCoordinator(
        read: () => room.state,
        delay: Duration.zero,
        isComputerSeat: isBot,
        onError: (error) => failure = error,
        commit: (before, after) {
          final bot = AiTurnCoordinator.actingSeat(before, isBot);
          final ack = room.move(
            bot,
            'bot-${before.events.length}',
            room.version,
            after.events.last.toJson(),
          );
          return ack['ok'] == true;
        },
      );
      ai.resume();
      await ai.settled.timeout(const Duration(seconds: 8));
      expect(failure, isNull);
      expect(room.state!.events.whereType<RespondTrade>(), isNotEmpty);
      expect(room.state!.offers, isEmpty);
    },
  );

  test('network snapshots animate public events but hide private history', () {
    final room = openRoom();
    final original = room.state!;
    room.state = original.copyWith(
      events: [
        const RollDice(2, 5),
        DiscardResources(1, {Resource.wood: 3, Resource.wheat: 1}),
        const PlayStrategyCard(4, target: 0, give: Resource.ore),
        const PlaceRoad(12),
      ],
    );
    final view = RoomProtocol.view(room.state!, 0);
    expect(view['events'], isEmpty);
    final exposed = view['publicEvents'] as List;
    expect(exposed, hasLength(4));
    expect(exposed[0], containsPair('type', 'roll'));
    expect(exposed[1], containsPair('type', 'redacted'));
    expect(exposed[2], containsPair('hand', -1));
    expect(exposed[2].toString(), isNot(contains('ore')));
    expect(exposed[3], containsPair('type', 'road'));
    final received = RoomProtocol.readView(view);
    expect(received.events, hasLength(4));
    expect(received.events[0], isA<RollDice>());
    expect(received.events[1], isA<RedactedNetworkEvent>());
    expect(received.events[2], isA<PlayStrategyCard>());
    expect(received.events.last, isA<PlaceRoad>());
    expect(received.seed, 0);
    expect(received.players[1].stores.values.every((n) => n == 0), true);
  });

  test('event decoder covers every Stage 5 response', () {
    for (final event in <MatchEvent>[
      const RespondTactical(1, 2, TacticalChoice.aid, good: Resource.ore),
      const ProposeTrade(1, Resource.wood, 3, Resource.wool, 2),
      const RespondTrade(1, false, offerId: 4),
      const PlayStrategyCard(0, target: 2, receive: Resource.wheat),
      const MoveBandit(2, victim: 1),
    ]) {
      expect(
        RoomProtocol.eventFromJson(event.toJson()).toJson(),
        event.toJson(),
      );
    }
  });
}
