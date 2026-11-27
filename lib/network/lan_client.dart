import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../engine/match.dart';
import 'room_protocol.dart';

class LanRoomClient extends ChangeNotifier {
  LanRoomClient({this.onSession});
  final void Function(String url, String room, String token)? onSession;

  WebSocketChannel? _socket;
  int _connectionGeneration = 0;
  Timer? _retry;
  Map<String, Object?>? _firstMessage;
  Map<String, Object?>? _outstanding;
  bool _disposed = false;
  String url = '';
  String? room, token, error;
  int? seat;
  int capacity = 3, version = 0, botCount = 0, generation = 0;
  List<int> botSeats = [];
  List<String> players = [];
  List<bool> connectedPlayers = [];
  MatchState? game;
  Map<String, dynamic>? view;
  List<dynamic> history = [];
  int? _turnRemainingMs;
  final _turnClock = Stopwatch();
  int? get turnSecondsRemaining => _turnRemainingMs == null
      ? null
      : ((_turnRemainingMs! - _turnClock.elapsedMilliseconds).clamp(0, 90000) /
                1000)
            .ceil();
  bool connected = false, connecting = false, pending = false, started = false;

  void host(String address, String name, int seats, int seed) => _connect(
    address,
    {'op': 'create', 'name': name, 'capacity': seats, 'boardSeed': seed},
  );
  void join(String address, String name, String code) => _connect(address, {
    'op': 'join',
    'name': name,
    'room': code.trim().toUpperCase(),
  });
  void resume(String address, String code, String recoveryToken) {
    room = code.trim().toUpperCase();
    token = recoveryToken.trim();
    _connect(address, {'op': 'resume', 'room': room, 'token': token});
  }

  void _connect(String address, Map<String, Object?> first) {
    _retry?.cancel();
    _socket?.sink.close();
    _socket = null;
    _connectionGeneration++;
    url = address.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty) {
      error = 'Enter a ws:// or wss:// host URL.';
      notifyListeners();
      return;
    }
    _firstMessage = first;
    error = null;
    connecting = true;
    connected = false;
    notifyListeners();
    _open();
  }

  Future<void> _open() async {
    if (_disposed || connected) return;
    final generation = _connectionGeneration;
    WebSocketChannel? socket;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      socket = channel;
      await channel.ready.timeout(const Duration(seconds: 5));
      if (_disposed || generation != _connectionGeneration) {
        await channel.sink.close();
        return;
      }
      _socket = channel;
      connected = true;
      connecting = false;
      error = null;
      notifyListeners();
      channel.stream.listen(
        (raw) {
          if (raw is! String || _disposed) return;
          try {
            _message(Map<String, dynamic>.from(jsonDecode(raw) as Map));
          } on Object catch (_) {
            error = 'Invalid host response.';
            notifyListeners();
          }
        },
        onDone: () => _disconnected(channel),
        onError: (_) => _disconnected(channel),
        cancelOnError: true,
      );
      _send(_firstMessage!);
    } on Object catch (_) {
      await socket?.sink.close();
      if (_disposed || generation != _connectionGeneration) return;
      connected = false;
      connecting = false;
      error = room == null ? 'Cannot reach that LAN host.' : null;
      notifyListeners();
      _scheduleRetry();
    }
  }

  void _disconnected(WebSocketChannel socket) {
    if (_disposed || _socket != socket) return;
    connected = false;
    connecting = false;
    _socket = null;
    if (socket.closeReason == 'Reconnected') {
      error = 'Session opened on another device.';
    } else {
      error = null;
      _scheduleRetry();
    }
    notifyListeners();
  }

  void _scheduleRetry() {
    if (room == null || token == null || _disposed) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), () {
      if (_disposed || connected) return;
      connecting = true;
      _firstMessage = {'op': 'resume', 'room': room, 'token': token};
      notifyListeners();
      _open();
    });
  }

  void _send(Map<String, Object?> message) {
    if (connected && _socket != null) {
      _socket!.sink.add(jsonEncode(message));
    }
  }

  void _message(Map<String, dynamic> msg) {
    switch (msg['op']) {
      case 'welcome':
        room = msg['room'] as String;
        token = msg['token'] as String;
        seat = msg['seat'] as int;
        _firstMessage = {'op': 'resume', 'room': room, 'token': token};
        onSession?.call(url, room!, token!);
        _send({'op': 'sync', 'from': version, 'generation': generation});
        if (_outstanding != null) _send(_outstanding!);
      case 'lobby':
        botCount = (msg['botCount'] as int?) ?? 0;
        botSeats = (msg['bots'] as List? ?? const []).cast<int>();
        capacity = msg['capacity'] as int;
        players = (msg['players'] as List).cast<String>();
        connectedPlayers = (msg['connected'] as List).cast<bool>();
        started = msg['started'] as bool;
      case 'state':
        final nextGeneration = (msg['generation'] as int?) ?? 0;
        if (nextGeneration != generation) {
          generation = nextGeneration;
          _outstanding = null;
          pending = false;
          history = [];
        }
        version = msg['version'] as int;
        _turnRemainingMs = msg['turnRemainingMs'] as int?;
        _turnClock
          ..reset()
          ..start();
        view = Map<String, dynamic>.from(msg['view'] as Map);
        game = RoomProtocol.readView(view!);
      case 'history':
        history = (msg['events'] as List);
      case 'ack':
        if (_outstanding?['id'] == msg['id']) {
          _outstanding = null;
          pending = false;
          if (msg['ok'] != true) {
            error = (msg['error'] as String?) ?? 'Move was rejected.';
            _send({'op': 'sync', 'from': version, 'generation': generation});
          }
        }
      case 'error':
        error = (msg['message'] as String?) ?? 'Room error.';
    }
    notifyListeners();
  }

  void start() => _send({'op': 'start'});
  void playAgain() => _send({'op': 'playAgain', 'generation': generation});
  void setBots(int count) => _send({'op': 'setBots', 'count': count});

  void dispatch(MatchEvent event) {
    if (!connected || pending || game == null) return;
    final random = Random.secure();
    final id = [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    _outstanding = {
      'op': 'move',
      'id': id,
      'base': version,
      'generation': generation,
      'event': event.toJson(),
    };
    pending = true;
    error = null;
    _send(_outstanding!);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _connectionGeneration++;
    _socket?.sink.close();
    super.dispose();
  }
}
