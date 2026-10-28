import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../engine/match.dart';
import 'room_protocol.dart';

class LanRoomClient extends ChangeNotifier {
  LanRoomClient({this.onSession});
  final void Function(String url, String room, String token)? onSession;

  WebSocket? _socket;
  Timer? _retry;
  Map<String, Object?>? _firstMessage;
  Map<String, Object?>? _outstanding;
  bool _disposed = false;
  String url = '';
  String? room, token, error;
  int? seat;
  int capacity = 3, version = 0;
  List<String> players = [];
  List<bool> connectedPlayers = [];
  MatchState? game;
  Map<String, dynamic>? view;
  List<dynamic> history = [];
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
    _socket?.close();
    url = address.trim();
    if (Uri.tryParse(url)?.scheme != 'ws') {
      error = 'Use a ws:// LAN host URL.';
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
    try {
      final socket = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 5));
      if (_disposed) {
        socket.close();
        return;
      }
      _socket = socket;
      connected = true;
      connecting = false;
      error = null;
      notifyListeners();
      socket.listen(
        (raw) {
          if (raw is! String || _disposed) return;
          try {
            _message(Map<String, dynamic>.from(jsonDecode(raw) as Map));
          } on Object catch (_) {
            error = 'Invalid host response.';
            notifyListeners();
          }
        },
        onDone: () => _disconnected(socket),
        onError: (_) => _disconnected(socket),
        cancelOnError: true,
      );
      _send(_firstMessage!);
    } on Object catch (_) {
      connected = false;
      connecting = false;
      error = room == null ? 'Cannot reach that LAN host.' : null;
      notifyListeners();
      _scheduleRetry();
    }
  }

  void _disconnected(WebSocket socket) {
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
    if (_socket?.readyState == WebSocket.open) {
      _socket!.add(jsonEncode(message));
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
        _send({'op': 'sync', 'from': version});
        if (_outstanding != null) _send(_outstanding!);
      case 'lobby':
        capacity = msg['capacity'] as int;
        players = (msg['players'] as List).cast<String>();
        connectedPlayers = (msg['connected'] as List).cast<bool>();
        started = msg['started'] as bool;
      case 'state':
        version = msg['version'] as int;
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
            _send({'op': 'sync', 'from': version});
          }
        }
      case 'error':
        error = (msg['message'] as String?) ?? 'Room error.';
    }
    notifyListeners();
  }

  void start() => _send({'op': 'start'});

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
    _socket?.close();
    super.dispose();
  }
}
