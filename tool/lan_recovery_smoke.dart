import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';

class _Peer {
  _Peer(this.socket) : messages = StreamIterator<dynamic>(socket);
  final WebSocket socket;
  final StreamIterator<dynamic> messages;

  static Future<_Peer> connect(String url) async =>
      _Peer(await WebSocket.connect(url).timeout(const Duration(seconds: 5)));

  void send(Map<String, Object?> value) => socket.add(jsonEncode(value));

  Future<Map<String, dynamic>> until(String op, {int? version}) async {
    while (await messages.moveNext().timeout(const Duration(seconds: 6))) {
      final data =
          jsonDecode(messages.current as String) as Map<String, dynamic>;
      if (data['op'] == 'error') {
        throw StateError('Host error: ${data['message']}');
      }
      if (data['op'] == op && (version == null || data['version'] == version)) {
        return data;
      }
    }
    throw StateError('Host closed before $op (version $version).');
  }

  Future<void> close() async {
    try {
      await socket.close().timeout(const Duration(seconds: 2));
    } on Object catch (_) {}
    await messages.cancel();
  }
}

Future<Process> _start(int port, String directory) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    'tool/lan_server.dart',
    '--port',
    '$port',
    '--state-dir',
    directory,
  ]);
  final ready = await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 20));
  if (!ready.contains('LAN host')) {
    throw StateError('Unexpected host startup: $ready');
  }
  return process;
}

Future<void> _kill(Process process) async {
  process.kill();
  await process.exitCode.timeout(const Duration(seconds: 5));
}

void _check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('stone-lan-recovery-');
  final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = reserved.port;
  await reserved.close();
  final url = 'ws://127.0.0.1:$port/room';
  Process? server;
  final peers = <_Peer>[];
  try {
    server = await _start(port, temp.path);
    for (var i = 0; i < 3; i++) {
      peers.add(await _Peer.connect(url));
    }
    peers[0].send({
      'op': 'create',
      'capacity': 3,
      'boardSeed': 42,
      'name': 'Ada',
    });
    final owner = await peers[0].until('welcome');
    final roomCode = owner['room'] as String;
    final tokens = <String>[owner['token'] as String];
    for (var i = 1; i < 3; i++) {
      peers[i].send({
        'op': 'join',
        'room': roomCode,
        'name': i == 1 ? 'Ben' : 'Cora',
      });
      tokens.add((await peers[i].until('welcome'))['token'] as String);
    }
    peers[0].send({'op': 'start'});
    var states = [for (final p in peers) await p.until('state', version: 0)];
    var current = RoomProtocol.readView(
      Map<String, dynamic>.from(states[0]['view'] as Map),
    );
    final first = PlaceVillage(MatchEngine.legalVertices(current).first);
    peers[1].send({
      'op': 'move',
      'id': 'wrong-seat',
      'base': 0,
      'event': first.toJson(),
    });
    _check(
      (await peers[1].until('ack'))['ok'] == false,
      'Wrong-seat command accepted',
    );

    Map<String, Object?>? firstRequest;
    Map<String, dynamic>? firstAck;
    for (var revision = 0; revision < 12; revision++) {
      final actor = current.active;
      final event = current.phase == MatchPhase.setupVillage
          ? PlaceVillage(MatchEngine.legalVertices(current).first)
          : PlaceRoad(MatchEngine.legalEdges(current).first);
      final request = <String, Object?>{
        'op': 'move',
        'id': 'setup-$revision',
        'base': revision,
        'event': event.toJson(),
      };
      if (revision == 0) firstRequest = request;
      peers[actor].send(request);
      final ack = await peers[actor].until('ack');
      _check(
        ack['ok'] == true && ack['version'] == revision + 1,
        'Host rejected legal setup at $revision: $ack',
      );
      if (revision == 0) firstAck = ack;
      states = [
        for (final p in peers) await p.until('state', version: revision + 1),
      ];
      for (var seat = 0; seat < 3; seat++) {
        final view = states[seat]['view'] as Map;
        _check(
          view['seed'] == 0 &&
              (view['events'] as List).isEmpty &&
              (view['drawPiles'] as Map).isEmpty,
          'Private host data leaked to seat $seat',
        );
        for (var rival = 0; rival < 3; rival++) {
          if (rival == seat) continue;
          final other = (view['players'] as List)[rival] as Map;
          _check(
            (other['cards'] as List).isEmpty &&
                (other['resources'] as List).every((v) => v == 0),
            'Hidden rival hand exposed to seat $seat',
          );
        }
      }
      // Public board geometry is enough to choose each setup action.
      current = RoomProtocol.readView(
        Map<String, dynamic>.from(states[0]['view'] as Map),
      );
    }
    _check(current.phase == MatchPhase.roll, 'Setup did not finish');
    peers[0].send(firstRequest!);
    _check(
      (await peers[0].until('ack'))['version'] == firstAck!['version'],
      'Duplicate original move changed its acknowledgement',
    );
    peers[0].send({
      'op': 'move',
      'id': 'stale-new',
      'base': 0,
      'event': first.toJson(),
    });
    _check(
      (await peers[0].until('ack'))['ok'] == false,
      'Fresh stale move was accepted',
    );

    await peers[1].close();
    peers[1] = await _Peer.connect(url);
    peers[1].send({'op': 'resume', 'room': roomCode, 'token': tokens[1]});
    _check(
      (await peers[1].until('welcome'))['seat'] == 1,
      'Guest restart lost seat',
    );
    _check(
      (await peers[1].until('state', version: 12))['version'] == 12,
      'Guest restart lost revision',
    );

    await _kill(server);
    server = await _start(port, temp.path);
    for (var i = 0; i < 3; i++) {
      await peers[i].close();
      peers[i] = await _Peer.connect(url);
      peers[i].send({'op': 'resume', 'room': roomCode, 'token': tokens[i]});
      _check(
        (await peers[i].until('welcome'))['seat'] == i,
        'Host restart lost seat $i',
      );
    }
    states = [for (final p in peers) await p.until('state', version: 12)];
    peers[0].send(firstRequest);
    final afterRestart = await peers[0].until('ack');
    _check(
      afterRestart['ok'] == true &&
          afterRestart['version'] == firstAck['version'],
      'Replaying accepted ID after host restart changed history',
    );

    var version = 12;
    for (var turn = 0; turn < 3; turn++) {
      while (true) {
        final state = RoomProtocol.readView(
          Map<String, dynamic>.from(states[0]['view'] as Map),
        );
        final window = state.tactical;
        final MatchEvent event = window != null
            ? RespondTactical(window.id, window.responder, TacticalChoice.pass)
            : switch (state.phase) {
                MatchPhase.roll => const RollDice(0, 0),
                MatchPhase.bandit => MoveBandit(
                  (state.banditTile + 1) % state.board.tiles.length,
                ),
                MatchPhase.actions => const EndTurn(),
                MatchPhase.invasion => const ResolveInvasion(),
                _ => throw StateError('Unexpected turn phase ${state.phase}'),
              };
        final actor = window?.responder ?? state.active;
        peers[actor].send({
          'op': 'move',
          'id': 'turn-$turn-$version',
          'base': version,
          'event': event.toJson(),
        });
        final ack = await peers[actor].until('ack');
        _check(
          ack['ok'] == true && ack['version'] == version + 1,
          'Turn event rejected: $ack',
        );
        version++;
        states = [
          for (final p in peers) await p.until('state', version: version),
        ];
        final next = RoomProtocol.readView(
          Map<String, dynamic>.from(states[0]['view'] as Map),
        );
        if (next.phase == MatchPhase.roll && next.active != actor) break;
      }
    }
    _check(version > 15, 'No full turn progression');
    stdout.writeln(
      'PASS: 3 real sockets, 12-event draft, filtered views, '
      'wrong-seat/stale/duplicate, guest reconnect, server restart, '
      'persisted dedupe, 3 complete turns; revision $version',
    );
  } finally {
    for (final p in peers) {
      await p.close();
    }
    if (server != null) {
      try {
        await _kill(server);
      } on Object catch (_) {}
    }
    await temp.delete(recursive: true);
  }
}
