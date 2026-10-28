import 'dart:convert';
import 'dart:math';

import '../engine/match.dart';
import 'room_protocol.dart';

String _secret(int bytes) {
  final random = Random.secure();
  return [
    for (var i = 0; i < bytes; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

class RoomSeat {
  RoomSeat(this.name, this.token);
  final String name, token;
  bool connected = false;
}

/// One single-isolate, authoritative room. No client is allowed to mutate state.
class HostedRoom {
  HostedRoom(this.id, this.capacity, this.boardSeed)
    : assert(capacity == 3 || capacity == 4),
      secretSeed =
          Random.secure().nextInt(1 << 32) |
          (Random.secure().nextInt(1 << 30) << 32);

  final String id;
  final int capacity, boardSeed, secretSeed;
  final seats = <RoomSeat>[];
  MatchState? state;
  final _responses = <int, Map<String, (String, Map<String, Object?>)>>{};
  final _audit = <Map<String, Object?>>[];

  int get version => state?.events.length ?? 0;

  RoomSeat join(String name) {
    if (state != null) throw StateError('Match already started.');
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 32) {
      throw StateError('Name must be 1–32 characters.');
    }
    if (seats.any((s) => s.name.toLowerCase() == clean.toLowerCase())) {
      throw StateError('Choose a distinct player name.');
    }
    if (seats.length >= capacity) throw StateError('Room is full.');
    final seat = RoomSeat(clean, _secret(32));
    seats.add(seat);
    return seat;
  }

  int seatFor(String token) => seats.indexWhere((seat) => seat.token == token);

  Map<String, Object?> lobby() => {
    'op': 'lobby',
    'room': id,
    'capacity': capacity,
    'players': [for (final s in seats) s.name],
    'connected': [for (final s in seats) s.connected],
    'started': state != null,
  };

  void start(int seat) {
    if (seat != 0) throw StateError('Only the room creator can start.');
    if (state != null) return;
    if (seats.length != capacity) {
      throw StateError('Wait for all $capacity players.');
    }
    state = MatchEngine.newGame(
      [for (final s in seats) s.name],
      secretSeed,
      boardSeed: boardSeed,
    );
  }

  Map<String, Object?> move(
    int seat,
    String id,
    int base,
    Map<String, dynamic> wire,
  ) {
    if (id.isEmpty || id.length > 128) {
      return {
        'op': 'ack',
        'id': id,
        'ok': false,
        'error': 'Invalid request ID.',
      };
    }
    final canonical = jsonEncode({'base': base, 'event': wire});
    final cached = _responses.putIfAbsent(seat, () => {})[id];
    if (cached != null) {
      return cached.$1 == canonical
          ? cached.$2
          : {'op': 'ack', 'id': id, 'ok': false, 'error': 'Reused request ID.'};
    }
    Map<String, Object?> reply;
    try {
      final current = state;
      if (current == null) throw StateError('Match not started.');
      if (base != version) throw StateError('Stale view; resynchronise.');
      final input = RoomProtocol.eventFromJson(wire);
      final event = input is RollDice
          ? RollDice(
              MatchEngine.expectedDice(current).$1,
              MatchEngine.expectedDice(current).$2,
            )
          : input;
      if (event is TimeoutTactical) {
        throw StateError('Only the server schedules timeouts.');
      }
      if (current.tactical case final TacticalWindow window) {
        if (event is! RespondTactical ||
            window.responder != seat ||
            event.player != seat) {
          throw StateError('Waiting for the named tactical responder.');
        }
      } else if (seat != current.active ||
          (event is RespondTactical) ||
          (event is RespondTrade && event.player != seat)) {
        throw StateError('This is another player’s turn.');
      }
      state = MatchEngine.apply(current, event); // Final legality authority.
      _record(event, seat);
      reply = {'op': 'ack', 'id': id, 'ok': true, 'version': version};
    } on Object catch (error) {
      reply = {
        'op': 'ack',
        'id': id,
        'ok': false,
        'version': version,
        'error': error is StateError ? error.message : 'Invalid move.',
      };
    }
    _responses[seat]![id] = (canonical, reply);
    return reply;
  }

  bool timeout(int windowId, int responder) {
    final current = state;
    if (current?.tactical?.id != windowId ||
        current?.tactical?.responder != responder) {
      return false;
    }
    final event = TimeoutTactical(windowId, responder);
    state = MatchEngine.apply(current!, event);
    _record(event, responder);
    return true;
  }

  /// Bounded inactivity policy for all turns, including disconnected seats.
  bool advanceIdle(int expectedVersion) {
    final current = state;
    if (current == null ||
        version != expectedVersion ||
        current.phase == MatchPhase.finished ||
        current.tactical != null) {
      return false;
    }
    final MatchEvent event = switch (current.phase) {
      MatchPhase.setupVillage => PlaceVillage(
        MatchEngine.legalVertices(current).first,
      ),
      MatchPhase.setupRoad => PlaceRoad(MatchEngine.legalEdges(current).first),
      MatchPhase.roll => RollDice(
        MatchEngine.expectedDice(current).$1,
        MatchEngine.expectedDice(current).$2,
      ),
      MatchPhase.bandit => MoveBandit(
        (current.banditTile + 1) % current.board.tiles.length,
      ),
      MatchPhase.actions => const EndTurn(),
      MatchPhase.invasion => const ResolveInvasion(),
      MatchPhase.finished => throw StateError('Match finished.'),
    };
    state = MatchEngine.apply(current, event);
    _record(event, current.active);
    return true;
  }

  void _record(MatchEvent event, int actor) {
    _audit.add({
      'seq': version,
      'actor': actor,
      'kind': event.toJson()['type'],
      if (event is RollDice) 'total': event.first + event.second,
      if (event is ProposeTrade) 'offer': event.toJson(),
      if (event is RespondTrade) 'offerId': event.offerId,
    });
  }

  List<Map<String, Object?>> historyAfter(int sequence) => [
    for (final entry in _audit)
      if ((entry['seq'] as int) > sequence) entry,
  ];

  /// For host-only audit/backup, never transmit or log this to clients.
  String privateReplay() => MatchEngine.exportReplay(state!);

  MatchState replayOnHost() => MatchEngine.importReplay(privateReplay());
}

class LanRoomRegistry {
  final rooms = <String, HostedRoom>{};

  HostedRoom create(int capacity, int boardSeed, String name) {
    if (capacity != 3 && capacity != 4) throw StateError('Use 3–4 seats.');
    if (rooms.length >= 64) throw StateError('Host is at room capacity.');
    String code;
    do {
      code = _secret(5).substring(0, 8).toUpperCase();
    } while (rooms.containsKey(code));
    final room = HostedRoom(code, capacity, boardSeed);
    room.join(name);
    rooms[code] = room;
    return room;
  }

  HostedRoom find(String code) {
    final room = rooms[code.toUpperCase()];
    if (room == null) throw StateError('Room not found.');
    return room;
  }
}
