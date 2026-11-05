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

  HostedRoom.restored(this.id, this.capacity, this.boardSeed, this.secretSeed)
    : assert(capacity == 3 || capacity == 4);

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

  /// Host-only room checkpoint. Never include this in a client response or log.
  Map<String, Object?> toPrivateJson() => {
    'format': 'stone-and-banner-room-v1',
    'id': id,
    'capacity': capacity,
    'boardSeed': boardSeed,
    'secretSeed': secretSeed,
    'version': version,
    'seats': [
      for (final seat in seats) {'name': seat.name, 'token': seat.token},
    ],
    'replay': state == null ? null : privateReplay(),
    'audit': _audit,
    'responses': {
      for (final entry in _responses.entries)
        '${entry.key}': [
          for (final response in entry.value.entries)
            {
              'id': response.key,
              'canonical': response.value.$1,
              'reply': response.value.$2,
            },
        ],
    },
  };

  /// Fail closed on a damaged checkpoint instead of silently replacing a room.
  static HostedRoom fromPrivateJson(Map<String, dynamic> data) {
    if (data['format'] != 'stone-and-banner-room-v1') {
      throw const FormatException('Unknown LAN room checkpoint format.');
    }
    final id = data['id'] as String;
    final capacity = data['capacity'] as int;
    final boardSeed = data['boardSeed'] as int;
    final secretSeed = data['secretSeed'] as int;
    if (!RegExp(r'^[0-9A-F]{8}$').hasMatch(id) ||
        (capacity != 3 && capacity != 4)) {
      throw const FormatException('Invalid LAN room identity.');
    }
    final room = HostedRoom.restored(id, capacity, boardSeed, secretSeed);
    for (final raw in data['seats'] as List) {
      final seat = Map<String, dynamic>.from(raw as Map);
      final name = seat['name'] as String;
      final token = seat['token'] as String;
      if (name.trim() != name ||
          name.isEmpty ||
          name.length > 32 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(token) ||
          room.seats.any(
            (other) =>
                other.name.toLowerCase() == name.toLowerCase() ||
                other.token == token,
          ) ||
          room.seats.length >= capacity) {
        throw const FormatException('Invalid LAN room seat.');
      }
      room.seats.add(RoomSeat(name, token)); // All offline on host restart.
    }
    final replay = data['replay'] as String?;
    if (replay != null) {
      if (room.seats.length != capacity) {
        throw const FormatException('Started room has incomplete seats.');
      }
      room.state = MatchEngine.importReplay(replay);
      if (room.state!.seed != secretSeed ||
          room.state!.board.seed != boardSeed ||
          room.state!.players.length != capacity ||
          [for (final p in room.state!.players) p.id].join('\u0000') !=
              [for (final s in room.seats) s.name].join('\u0000')) {
        throw const FormatException('LAN room replay identity mismatch.');
      }
    }
    if (room.version != data['version']) {
      throw const FormatException('LAN room version mismatch.');
    }
    for (final raw in data['audit'] as List) {
      final entry = Map<String, Object?>.from(raw as Map);
      if (entry['seq'] != room._audit.length + 1) {
        throw const FormatException('LAN room audit sequence mismatch.');
      }
      room._audit.add(entry);
    }
    if (room._audit.length != room.version) {
      throw const FormatException('LAN room audit length mismatch.');
    }
    final responseData = Map<String, dynamic>.from(data['responses'] as Map);
    for (final entry in responseData.entries) {
      final seat = int.tryParse(entry.key);
      if (seat == null || seat < 0 || seat >= room.seats.length) {
        throw const FormatException('Invalid LAN room response seat.');
      }
      final cache = <String, (String, Map<String, Object?>)>{};
      for (final raw in entry.value as List) {
        final response = Map<String, dynamic>.from(raw as Map);
        final key = response['id'] as String;
        if (key.isEmpty || key.length > 128 || cache.containsKey(key)) {
          throw const FormatException('Invalid LAN request cache.');
        }
        cache[key] = (
          response['canonical'] as String,
          Map<String, Object?>.from(response['reply'] as Map),
        );
      }
      room._responses[seat] = cache;
    }
    return room;
  }

  /// For host-only audit/backup, never transmit or log this to clients.
  String privateReplay() => MatchEngine.exportReplay(state!);

  MatchState replayOnHost() => MatchEngine.importReplay(privateReplay());
}

class LanRoomRegistry {
  final rooms = <String, HostedRoom>{};

  void restore(HostedRoom room) {
    if (rooms.length >= 64 || rooms.containsKey(room.id)) {
      throw StateError('Duplicate room or host capacity exceeded.');
    }
    rooms[room.id] = room;
  }

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
