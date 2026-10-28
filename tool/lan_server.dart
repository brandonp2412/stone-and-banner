import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_host.dart';
import 'package:stone_and_banner/network/room_protocol.dart';

/// CLI LAN host. Defaults to loopback; explicit --bind required for LAN.
Future<void> main(List<String> args) async {
  var bind = '127.0.0.1', port = 8765;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--bind' && i + 1 < args.length) {
      bind = args[++i];
    } else if (args[i] == '--port' && i + 1 < args.length) {
      port = int.parse(args[++i]);
    } else {
      throw FormatException(
        'Usage: dart run tool/lan_server.dart '
        '[--bind 127.0.0.1|LAN_IP] [--port 8765]',
      );
    }
  }
  final host = await HttpServer.bind(InternetAddress(bind), port);
  final server = _Server();
  stdout.writeln('Stone & Banner LAN host on $bind:$port (no TLS)');
  await for (final request in host) {
    if (request.uri.path != '/room' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    server.attach(socket);
  }
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

class _Server {
  final registry = LanRoomRegistry();
  final connections = <_Connection>{};
  final clocks = <HostedRoom, Timer>{};

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
      case 'start':
        final fresh = room.state == null;
        room.start(seat);
        broadcast(room);
        if (fresh) schedule(room);
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
            schedule(room);
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
      'view': RoomProtocol.view(room.state!, conn.seat!),
    });
  }

  void broadcast(HostedRoom room) {
    for (final conn in connections) {
      if (conn.room != room) continue;
      conn.send(room.lobby());
      sendState(conn);
    }
  }

  void disconnect(_Connection conn) {
    if (!connections.remove(conn)) return;
    if (conn.room case final HostedRoom room) {
      room.seats[conn.seat!].connected = false;
      broadcast(room);
    }
  }

  void schedule(HostedRoom room) {
    clocks.remove(room)?.cancel();
    final state = room.state;
    if (state == null || state.phase == MatchPhase.finished) return;
    final window = state.tactical;
    if (window != null) {
      final id = window.id, responder = window.responder;
      clocks[room] = Timer(const Duration(seconds: 20), () {
        if (room.timeout(id, responder)) {
          broadcast(room);
          schedule(room);
        }
      });
    } else {
      final version = room.version;
      clocks[room] = Timer(const Duration(minutes: 3), () {
        if (room.advanceIdle(version)) {
          broadcast(room);
          schedule(room);
        }
      });
    }
  }
}
