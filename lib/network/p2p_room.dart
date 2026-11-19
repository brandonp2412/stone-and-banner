import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../engine/match.dart';
import 'p2p_links.dart';
import 'p2p_transport.dart';
import 'room_host.dart';
import 'room_protocol.dart';

String _randomId(int bytes) {
  final rng = Random.secure();
  return [
    for (var i = 0; i < bytes; i++)
      rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// One authoritative host browser, with private views sent over WebRTC.
class P2pRoom extends ChangeNotifier {
  P2pRoom() {
    _rtc = P2pTransport(_onEvent);
    _rtc.listenAnswers((link) {
      if (_disposed || !isHost) return;
      acceptAnswer(link).catchError((Object error) {
        if (_disposed) return;
        message = 'Cannot accept response: $error';
        notifyListeners();
      });
    });
  }

  late final P2pTransport _rtc;
  HostedRoom? _room;
  final Map<String, int> _peerSeats = {};
  final Set<String> _invited = {};
  final Set<String> _answered = {};
  final Set<String> _open = {};
  Timer? _clock;
  String? _clockKey;
  String _guestName = 'Player';
  bool _disposed = false;

  bool isHost = false, connected = false, pending = false, preparing = false;
  String? message, roomId, invitationLink, answerLink, guestPeer;
  int capacity = 3, version = 0;
  int? seat;
  bool started = false;
  List<String> players = [];
  List<bool> connectedPlayers = [];
  MatchState? game;
  Map<String, dynamic>? view;

  void host(String name, int seats, int seed) {
    if (_room != null || guestPeer != null) {
      throw StateError('Already in a room.');
    }
    _room = LanRoomRegistry().create(seats, seed, name);
    _room!.seats[0].connected = true;
    isHost = true;
    connected = true;
    roomId = _room!.id;
    seat = 0;
    _refreshHost();
    notifyListeners();
  }

  /// One unique invitation per remote participant. Host browser must remain open.
  Future<void> invite() async {
    final room = _room;
    if (!isHost || room == null || started) {
      throw StateError('Open a host lobby first.');
    }
    if (_invited.length + 1 >= capacity) {
      throw StateError('All remote seats already have invitations.');
    }
    preparing = true;
    message = null;
    notifyListeners();
    final id = _randomId(12);
    try {
      final sdp = await _rtc.offer(id);
      if (_disposed) return;
      _invited.add(id);
      invitationLink = P2pLinks.link(Uri.base, {
        'type': 'offer',
        'room': room.id,
        'peer': id,
        'sdp': sdp,
      });
    } on Object catch (e) {
      _rtc.close(id);
      message = 'Cannot create invitation: $e';
    } finally {
      preparing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> join(String name, Map<String, dynamic> offer) async {
    if (_room != null || guestPeer != null) {
      throw StateError('Already in a room.');
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 32) {
      throw StateError('Name must be 1–32 characters.');
    }
    if (offer['type'] != 'offer') {
      throw const FormatException('Expected a host invitation.');
    }
    _guestName = cleanName;
    roomId = offer['room'] as String;
    guestPeer = offer['peer'] as String;
    preparing = true;
    message = null;
    notifyListeners();
    try {
      final sdp = await _rtc.answer(guestPeer!, offer['sdp'] as String);
      if (_disposed) return;
      answerLink = P2pLinks.link(Uri.base, {
        'type': 'answer',
        'room': roomId,
        'peer': guestPeer,
        'sdp': sdp,
      });
    } on Object catch (e) {
      _rtc.close(guestPeer!);
      guestPeer = null;
      message = 'Cannot respond to invitation: $e';
    } finally {
      preparing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> acceptAnswer(String response) async {
    final data = P2pLinks.parse(response);
    final id = data['peer'] as String;
    if (!isHost ||
        data['type'] != 'answer' ||
        data['room'] != roomId ||
        !_invited.contains(id) ||
        _answered.contains(id)) {
      throw StateError('Response does not match a pending invitation.');
    }
    _answered.add(id);
    try {
      await _rtc.accept(id, data['sdp'] as String);
      if (_disposed) return;
      message = null;
    } on Object {
      _answered.remove(id);
      rethrow;
    }
    notifyListeners();
  }

  void _onEvent(String peer, String type, String raw) {
    if (_disposed) return;
    switch (type) {
      case 'open':
        _open.add(peer);
        if (!isHost && peer == guestPeer) {
          _send(peer, {'op': 'hello', 'name': _guestName});
        }
      case 'close':
        _open.remove(peer);
        if (isHost && _peerSeats.containsKey(peer)) {
          final seat = _peerSeats[peer]!;
          _room!.seats[seat].connected = false;
          _broadcast();
        } else if (!isHost && peer == guestPeer) {
          connected = false;
          message = 'Connection lost. Host and guests must keep their browser tabs open.';
        }
      case 'error':
        message = raw;
      case 'message':
        try {
          if (raw.length > 131072) {
            throw const FormatException('Oversized peer message.');
          }
          final msg = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          if (isHost) {
            _hostMessage(peer, msg);
          } else if (peer == guestPeer) {
            _guestMessage(msg);
          }
        } on Object catch (e) {
          message = 'Peer message rejected: $e';
        }
    }
    notifyListeners();
  }

  void _send(String peer, Map<String, Object?> msg) {
    if (_open.contains(peer)) _rtc.send(peer, jsonEncode(msg));
  }

  void _hostMessage(String peer, Map<String, dynamic> msg) {
    final room = _room!;
    if (msg['op'] == 'hello') {
      if (!_answered.contains(peer) || _peerSeats.containsKey(peer)) return;
      if (msg['name'] is! String) {
        throw const FormatException('Invalid player name.');
      }
      final number = room.seats.length;
      try {
        room.join(msg['name'] as String);
      } on StateError catch (error) {
        _send(peer, {'op': 'error', 'message': error.message});
        return;
      }
      room.seats[number].connected = true;
      message = null;
      _peerSeats[peer] = number;
      _send(peer, {'op': 'welcome', 'room': room.id, 'seat': number});
      _broadcast();
      return;
    }
    final seat = _peerSeats[peer];
    if (seat == null) return;
    switch (msg['op']) {
      case 'move':
        if (msg['id'] is! String ||
            msg['base'] is! int ||
            msg['event'] is! Map) {
          return;
        }
        final before = room.version;
        final reply = room.move(
          seat,
          msg['id'] as String,
          msg['base'] as int,
          Map<String, dynamic>.from(msg['event'] as Map),
        );
        _send(peer, reply);
        if (room.version != before) {
          _broadcast();
          _schedule();
        } else {
          _stateFor(peer, seat);
        }
      case 'sync':
        _stateFor(peer, seat);
      default:
        message = 'Unknown peer operation.';
    }
  }

  void _guestMessage(Map<String, dynamic> msg) {
    switch (msg['op']) {
      case 'welcome':
        if (msg['room'] != roomId || msg['seat'] is! int) return;
        seat = msg['seat'] as int;
        connected = true;
        message = null;
      case 'lobby':
        capacity = msg['capacity'] as int;
        players = (msg['players'] as List).cast<String>();
        connectedPlayers = (msg['connected'] as List).cast<bool>();
        started = msg['started'] as bool;
      case 'state':
        version = msg['version'] as int;
        view = Map<String, dynamic>.from(msg['view'] as Map);
        game = RoomProtocol.readView(view!);
        pending = false;
      case 'ack':
        pending = false;
        if (msg['ok'] != true) {
          message = msg['error'] as String? ?? 'Move rejected.';
        }
      case 'error':
        message = msg['message'] as String? ?? 'Peer error.';
    }
  }

  void _stateFor(String peer, int seat) {
    final state = _room?.state;
    if (state != null) {
      _send(peer, {
        'op': 'state',
        'version': _room!.version,
        'view': RoomProtocol.view(state, seat),
      });
    }
  }

  void _refreshHost() {
    final room = _room!;
    started = room.state != null;
    players = [for (final s in room.seats) s.name];
    connectedPlayers = [for (final s in room.seats) s.connected];
    capacity = room.capacity;
    version = room.version;
    view = room.state == null ? null : RoomProtocol.view(room.state!, 0);
    game = view == null ? null : RoomProtocol.readView(view!);
  }

  void _broadcast() {
    _refreshHost();
    for (final peer in _peerSeats.keys) {
      _send(peer, _room!.lobby());
      _stateFor(peer, _peerSeats[peer]!);
    }
    notifyListeners();
  }

  /// Retry joining with a different unique name over the existing data channel.
  void retryName(String name) {
    final clean = name.trim();
    if (isHost || guestPeer == null || clean.isEmpty || clean.length > 32) {
      return;
    }
    _guestName = clean;
    message = null;
    _send(guestPeer!, {'op': 'hello', 'name': _guestName});
    notifyListeners();
  }

  void start() {
    if (_room == null) return;
    _room!.start(0);
    message = null;
    _broadcast();
    _schedule();
  }

  void dispatch(MatchEvent event) {
    if (!connected || pending || game == null) return;
    final id = _randomId(16);
    if (isHost) {
      final room = _room!;
      final reply = room.move(0, id, room.version, event.toJson());
      if (reply['ok'] == true) {
        _broadcast();
        _schedule();
      } else {
        message = reply['error'] as String?;
        notifyListeners();
      }
    } else if (guestPeer != null) {
      pending = true;
      _send(guestPeer!, {
        'op': 'move',
        'id': id,
        'base': version,
        'event': event.toJson(),
      });
      notifyListeners();
    }
  }

  void _schedule() {
    final room = _room;
    final state = room?.state;
    if (state == null || state.phase == MatchPhase.finished) {
      _clock?.cancel();
      return;
    }
    final key = [
      state.turnSerial,
      state.active,
      state.pendingDiscards.keys.join(','),
      state.tactical?.id,
      state.tactical?.responder,
    ].join(':');
    if (_clockKey == key && _clock?.isActive == true) return;
    _clock?.cancel();
    _clockKey = key;
    _clock = Timer(const Duration(seconds: 90), () {
      final current = room!.state;
      if (current == null) return;
      final tactical = current.tactical;
      final advanced = tactical != null
          ? room.timeout(tactical.id, tactical.responder)
          : room.advanceIdle(room.version);
      if (advanced) _broadcast();
      _schedule();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    _rtc.dispose();
    super.dispose();
  }
}
