import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'lan_discovery_targets.dart';

import '../engine/match.dart';
import '../engine/ai_turn_coordinator.dart';
import 'room_host.dart';
import 'room_protocol.dart';

/// Host lives in the game process, not a separate executable/server.
class LanHostServer {
  LanHostServer._(this._http, this._protocol, this._discovery);
  final HttpServer _http;
  final _LanServerProtocol _protocol;
  final RawDatagramSocket? _discovery;
  static const discoveryPort = 38745;
  static const discoveryRequest = 'stone-banner-discover-v1';
  int get port => _http.port;
  bool _closed = false;

  static Future<LanHostServer> start({
    String bindAddress = '0.0.0.0',
    int port = 0,
    bool advertise = true,
    bool shuffleTurns = true,
  }) async {
    final http = await HttpServer.bind(InternetAddress(bindAddress), port);
    final protocol = _LanServerProtocol(shuffleTurns: shuffleTurns);
    RawDatagramSocket? discovery;
    try {
      if (advertise) {
        discovery = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
          reuseAddress: true,
        );
        final receiver = discovery;
        receiver.listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? packet;
          while ((packet = receiver.receive()) != null) {
            final datagram = packet!;
            if (utf8.decode(datagram.data, allowMalformed: true) !=
                discoveryRequest) {
              continue;
            }
            final rooms = [
              for (final room in protocol.registry.rooms.values)
                if (room.state == null && room.seats.length < room.capacity)
                  {
                    'code': room.id,
                    'players': room.seats.length,
                    'capacity': room.capacity,
                  },
            ];
            receiver.send(
              utf8.encode(
                jsonEncode({
                  'app': discoveryRequest,
                  'port': http.port,
                  'rooms': rooms,
                }),
              ),
              datagram.address,
              datagram.port,
            );
          }
        });
      }
    } on SocketException {
      // Hosting still works even when this network forbids UDP discovery.
      discovery?.close();
      discovery = null;
    }
    final server = LanHostServer._(http, protocol, discovery);
    http.listen((request) async {
      try {
        if (request.uri.path != '/room' ||
            !WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        protocol.attach(socket);
      } on Object {
        // A disconnect during upgrade must not crash the room host.
      }
    });
    return server;
  }

  static Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final matches = <(int, String)>{};
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        final ip = address.address;
        if (address.isLoopback ||
            address.isLinkLocal ||
            !(ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                _is172Private(ip))) {
          continue;
        }
        final nic = iface.name.toLowerCase();
        final priority = nic.startsWith('wlan') || nic.startsWith('wifi')
            ? 0
            : nic.startsWith('eth') || nic.startsWith('en')
            ? 1
            : nic.startsWith('tun') || nic.startsWith('wg')
            ? 3
            : 2;
        matches.add((priority, ip));
      }
    }
    return (matches.toList()..sort((a, b) {
          final c = a.$1.compareTo(b.$1);
          return c == 0 ? a.$2.compareTo(b.$2) : c;
        }))
        .map((item) => item.$2)
        .toList();
  }

  static bool _is172Private(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4 || parts[0] != '172') return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }

  static Future<List<LanFoundRoom>> discover({
    Duration duration = const Duration(milliseconds: 2600),
  }) async {
    final found = <String, LanFoundRoom>{};
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = socket.receive()) != null) {
          try {
            final msg = jsonDecode(utf8.decode(packet!.data));
            if (msg is! Map ||
                msg['app'] != discoveryRequest ||
                msg['port'] is! int) {
              continue;
            }
            final ip = packet.address.address;
            final port = msg['port'] as int;
            if (port < 1 || port > 65535) continue;
            for (final room in msg['rooms'] as List? ?? const []) {
              if (room is! Map ||
                  room['code'] is! String ||
                  room['players'] is! int ||
                  room['capacity'] is! int) {
                continue;
              }
              final code = room['code'] as String;
              found['$ip:$port/$code'] = LanFoundRoom(
                ip,
                port,
                code,
                room['players'] as int,
                room['capacity'] as int,
              );
            }
          } on Object {
            /* Ignore unrelated or malformed LAN packets. */
          }
        }
      });
      final clock = Stopwatch()..start();
      final request = utf8.encode(discoveryRequest);
      void probe(String address) {
        try {
          socket.send(request, InternetAddress(address), discoveryPort);
        } on SocketException {
          // Another interface or a later retry can still succeed.
        }
      }

      // Keep the original protocol, and send directed broadcasts when the
      // operating system knows the interface's actual subnet.
      List<LanDiscoverySubnet> subnets = [];
      try {
        final raw = await const MethodChannel('stone_and_banner/lan')
            .invokeListMethod<dynamic>('subnets');
        subnets = LanDiscoverySubnet.fromPlatform(raw ?? []);
      } on Object {
        // Older runners and unsupported platforms retain broadcast discovery.
      }
      final broadcasts = {
        '255.255.255.255',
        for (final subnet in subnets) subnet.broadcast,
      };
      final initial = duration.inMilliseconds ~/ 4;
      for (var attempt = 0; attempt < 2; attempt++) {
        for (final target in broadcasts) {
          probe(target);
        }
        await Future<void>.delayed(Duration(milliseconds: initial));
      }
      // Some networks pass broadcast requests but drop their unicast replies.
      // Probe only the game's discovery port on a bounded on-link subnet,
      // and only when ordinary discovery did not find any rooms.
      if (found.isEmpty) {
        final targets = LanDiscoverySubnet.fallbackTargets(subnets);
        for (var offset = 0; offset < targets.length; offset += 16) {
          if (clock.elapsedMilliseconds >= duration.inMilliseconds) break;
          for (final target in targets.skip(offset).take(16)) {
            probe(target);
          }
          await Future<void>.delayed(const Duration(milliseconds: 8));
        }
      }
      final remaining = duration.inMilliseconds - clock.elapsedMilliseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
      return found.values.toList();
    } finally {
      socket.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _discovery?.close();
    _protocol.close();
    await _http.close(force: true);
  }
}

class LanFoundRoom {
  const LanFoundRoom(
    this.address,
    this.port,
    this.code,
    this.players,
    this.capacity,
  );
  final String address, code;
  final int port, players, capacity;
  String get invite => '$address:$port/$code';
  String get url => 'ws://$address:$port/room';
}

class _Connection {
  _Connection(this.socket);
  final WebSocket socket;
  HostedRoom? room;
  int? seat;

  void send(Map<String, Object?> value) {
    if (socket.readyState == WebSocket.open) socket.add(jsonEncode(value));
  }
}

class _LanServerProtocol {
  _LanServerProtocol({required this.shuffleTurns});
  final bool shuffleTurns;
  final registry = LanRoomRegistry();
  final botCounts = <HostedRoom, int>{};
  final botSeats = <HostedRoom, Set<int>>{};
  final botBrains = <HostedRoom, AiTurnCoordinator>{};
  static const botNames = ['Mira', 'Oswin', 'Tamsin', 'Alden', 'Briar'];

  void close() {
    for (final brain in botBrains.values) {
      brain.pause();
    }
    botBrains.clear();
    for (final clock in clocks.values) {
      clock.cancel();
    }
    clocks.clear();
    clockDeadlines.clear();
    for (final conn in connections.toList()) {
      conn.socket.close();
    }
    connections.clear();
  }

  final connections = <_Connection>{};
  final clocks = <HostedRoom, Timer>{};
  final clockTurns = <HostedRoom, String>{};
  final clockDeadlines = <HostedRoom, int>{};
  final clock = Stopwatch()..start();

  void attach(WebSocket socket) {
    final conn = _Connection(socket);
    connections.add(conn);
    socket.listen(
      (value) {
        try {
          if (value is! String || value.length > 16384) {
            throw const FormatException('Message is too large.');
          }
          final msg = Map<String, dynamic>.from(jsonDecode(value) as Map);
          handle(conn, msg);
        } on Object catch (error) {
          conn.send({
            'op': 'error',
            'message': error is StateError
                ? error.message
                : 'Malformed request.',
          });
        }
      },
      onError: (_) => disconnect(conn),
      onDone: () => disconnect(conn),
      cancelOnError: true,
    );
  }

  void handle(_Connection conn, Map<String, dynamic> msg) {
    final op = msg['op'];
    if (op == 'create' || op == 'join' || op == 'resume') {
      if (conn.room != null) throw StateError('Already attached to a room.');
      final HostedRoom room;
      final int seat;
      if (op == 'create') {
        room = registry.create(
          msg['capacity'] as int,
          msg['boardSeed'] as int,
          msg['name'] as String,
          shuffleTurns: shuffleTurns,
        );
        seat = 0;
      } else {
        room = registry.find(msg['room'] as String);
        if (op == 'resume') {
          seat = room.seatFor(msg['token'] as String);
          if (seat < 0) throw StateError('Invalid recovery token.');
        } else {
          seat = room.seats.length;
          room.join(msg['name'] as String);
          botCounts[room] = (botCounts[room] ?? 0).clamp(
            0,
            room.capacity - room.seats.length,
          );
        }
      }
      for (final previous in connections.toList()) {
        if (previous != conn &&
            previous.room == room &&
            previous.seat == seat) {
          previous.room = null;
          previous.socket.close(WebSocketStatus.normalClosure, 'Reconnected');
        }
      }
      conn.room = room;
      conn.seat = seat;
      room.seats[seat].connected = true;
      conn.send({
        'op': 'welcome',
        'room': room.id,
        'seat': seat,
        'token': room.seats[seat].token,
      });
      broadcast(room);
      return;
    }
    final room = conn.room;
    final seat = conn.seat;
    if (room == null || seat == null) throw StateError('Join a room first.');
    switch (op) {
      case 'setBots':
        if (seat != 0 || room.state != null) {
          throw StateError('Only the host can change bots before starting.');
        }
        final count = msg['count'];
        if (count is! int ||
            count < 0 ||
            count > room.capacity - room.seats.length) {
          throw StateError('Not enough seats for that many bots.');
        }
        botCounts[room] = count;
        broadcast(room);
      case 'start':
        final fresh = room.state == null;
        if (fresh) {
          if (seat != 0) throw StateError('Only the host can start.');
          final count = botCounts[room] ?? 0;
          if (room.seats.length + count != room.capacity) {
            throw StateError(
              'Connect players or add computers to fill every seat.',
            );
          }
          final assigned = <int>{};
          for (var i = 0; i < count; i++) {
            final index = room.seats.length;
            final name = botNames.firstWhere(
              (name) => !room.seats.any(
                (s) => s.name.toLowerCase() == name.toLowerCase(),
              ),
              orElse: () => 'Computer ${index + 1}',
            );
            room.join(name).connected = true;
            assigned.add(index);
          }
          botSeats[room] = assigned;
        }
        room.start(seat);
        broadcast(room);
      case 'move':
        final before = room.version;
        final reply = room.move(
          seat,
          msg['id'] as String,
          msg['base'] as int,
          Map<String, dynamic>.from(msg['event'] as Map),
        );
        conn.send(reply);
        if (reply['ok'] == true) {
          if (room.version != before) {
            broadcast(room);
          }
        } else {
          sendState(conn);
        }
      case 'sync':
        final from = (msg['from'] as int?) ?? 0;
        conn.send({
          'op': 'history',
          'room': room.id,
          'events': room.historyAfter(from < 0 ? 0 : from),
        });
        sendState(conn);
      default:
        throw StateError('Unknown operation.');
    }
  }

  void sendState(_Connection conn) {
    final room = conn.room!;
    if (room.state == null) return;
    conn.send({
      'op': 'state',
      'room': room.id,
      'version': room.version,
      if (clockDeadlines[room] case final int deadline)
        'turnRemainingMs': (deadline - clock.elapsedMilliseconds).clamp(
          0,
          90000,
        ),
      'view': RoomProtocol.view(room.state!, conn.seat!),
    });
  }

  void broadcast(HostedRoom room) {
    schedule(room);
    for (final conn in connections) {
      if (conn.room != room) continue;
      conn.send({
        ...room.lobby(),
        'botCount': botCounts[room] ?? 0,
        'bots': (botSeats[room] ?? <int>{}).toList(),
      });
      sendState(conn);
    }
    driveBots(room);
  }

  void driveBots(HostedRoom room) {
    final state = room.state;
    final computer = botSeats[room] ?? <int>{};
    final existing = botBrains[room];
    if (state == null ||
        state.phase == MatchPhase.finished ||
        computer.isEmpty ||
        !computer.contains(
          AiTurnCoordinator.actingSeat(state, computer.contains),
        )) {
      existing?.pause();
      return;
    }
    final brain = botBrains.putIfAbsent(
      room,
      () => AiTurnCoordinator(
        read: () => room.state,
        isComputerSeat: computer.contains,
        delay: const Duration(milliseconds: 450),
        commit: (previous, next) {
          if (!identical(room.state, previous) ||
              next.events.length != previous.events.length + 1) {
            return false;
          }
          final currentBot = AiTurnCoordinator.actingSeat(
            previous,
            computer.contains,
          );
          final result = room.move(
            currentBot,
            'bot-$currentBot-${room.version}',
            room.version,
            next.events.last.toJson(),
          );
          if (result['ok'] != true) return false;
          broadcast(room);
          return true;
        },
        onError: (error) {
          for (final conn in connections) {
            if (conn.room == room && conn.seat == 0) {
              conn.send({
                'op': 'error',
                'message': 'Computer player stopped: $error',
              });
            }
          }
        },
      ),
    );
    brain.resume();
  }

  void disconnect(_Connection conn) {
    if (!connections.remove(conn)) return;
    if (conn.room case final HostedRoom room) {
      room.seats[conn.seat!].connected = false;
      broadcast(room);
    }
  }

  void schedule(HostedRoom room) {
    final state = room.state;
    if (state == null || state.phase == MatchPhase.finished) {
      clocks.remove(room)?.cancel();
      clockTurns.remove(room);
      clockDeadlines.remove(room);
      return;
    }
    final key =
        '${state.turnSerial}:${state.active}:${state.pendingDiscards.keys.join(',')}:${state.tactical?.id}:${state.tactical?.responder}';
    // Offers and other actions must not renew a player's turn allowance.
    if (clockTurns[room] == key && clocks[room]?.isActive == true) return;
    clocks.remove(room)?.cancel();
    clockTurns[room] = key;
    clockDeadlines[room] = clock.elapsedMilliseconds + 90000;
    clocks[room] = Timer(const Duration(seconds: 90), () {
      final current = room.state;
      if (current == null) return;
      final window = current.tactical;
      final advanced = window != null
          ? room.timeout(window.id, window.responder)
          : room.advanceIdle(room.version);
      if (advanced) broadcast(room);
      schedule(room);
    });
  }
}
