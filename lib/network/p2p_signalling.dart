import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

typedef SignallingTrace = void Function(Map<String, Object?> entry);

/// Ephemeral WebRTC negotiation. Signalling diagnostics deliberately exclude
/// room keys, SDP, candidate IP addresses, access tokens and peer identifiers.
class P2pSignalling {
  P2pSignalling._(
    this._channel,
    this.onMessage,
    this.onError,
    this.onDiagnostic,
    this._attempt,
  ) {
    _subscription = _channel.stream.listen(
      (event) {
        if (event is! String || event.length > 20000) {
          _trace('invalid_response', detail: 'Malformed or oversized message');
          return;
        }
        try {
          final message = jsonDecode(event);
          if (message is! Map<String, dynamic>) {
            _trace('invalid_response', detail: 'Non-object signalling message');
            return;
          }
          final op = message['op'];
          switch (op) {
            case 'ready':
              _trace(
                'server_ready',
                code: message['protocol'] is int
                    ? 'protocol_${message['protocol']}'
                    : 'protocol_unknown',
              );
              if (!_ready.isCompleted) {
                _active = true;
                _ready.complete();
                _heartbeat ??= Timer.periodic(
                  const Duration(seconds: 25),
                  (_) => send({'op': 'ping'}),
                );
              }
              return;
            case 'pong':
              return;
            case 'error':
              _trace(
                'server_rejection',
                code: message['code'] is String
                    ? _safeText(message['code'] as String)
                    : 'unspecified',
                detail: message['message'] is String
                    ? _safeText(message['message'] as String)
                    : null,
              );
              if (!_ready.isCompleted) {
                _ready.completeError(
                  StateError(
                    message['message'] is String
                        ? _safeText(message['message'] as String)
                        : 'Signalling server rejected this connection.',
                  ),
                );
                return;
              }
            case 'waiting':
              _trace('host_waiting', code: 'host_offline');
            case 'host_online':
              _trace('host_available');
            case 'offer':
              _trace('offer_received');
            case 'answer':
              _trace('answer_received');
            case 'join':
              _trace('guest_join_requested');
            case 'left':
              _trace('guest_left');
          }
          if (!_closed) onMessage(message);
        } on Object catch (error) {
          _trace('decode_error', detail: _safeText('$error'));
          if (!_closed) onError('Invalid signalling response.');
        }
      },
      onError: (Object error) {
        _trace(
          'socket_error',
          code: '${error.runtimeType}',
          detail: _safeText('$error'),
        );
        if (!_ready.isCompleted) {
          _ready.completeError(error);
        } else if (!_closed && _active) {
          onError('Signalling socket error: ${error.runtimeType}');
        }
      },
      onDone: () {
        final code = _channel.closeCode;
        _trace(
          'socket_closed',
          code: code?.toString() ?? 'unknown',
          detail: _safeText(_channel.closeReason ?? 'No close reason'),
        );
        if (!_ready.isCompleted) {
          _ready.completeError(
            StateError(
              'Signalling connection closed before joining (code: $code).',
            ),
          );
        } else if (!_closed && _active) {
          onError('Signalling connection closed (code: $code).');
        }
      },
      cancelOnError: false,
    );
  }

  static const enabled = bool.fromEnvironment(
    'STONE_SIGNAL_ENABLED',
    defaultValue: bool.fromEnvironment('dart.vm.product'),
  );
  static const endpoint = String.fromEnvironment(
    'STONE_SIGNAL_URL',
    defaultValue: 'wss://stone-banner-signal.brandonp2412.workers.dev/signal/',
  );

  final WebSocketChannel _channel;
  final void Function(Map<String, dynamic>) onMessage;
  final void Function(String) onError;
  final SignallingTrace onDiagnostic;
  final int _attempt;
  final Completer<void> _ready = Completer<void>();
  late final StreamSubscription<dynamic> _subscription;
  Timer? _heartbeat;
  bool _closed = false;
  bool _active = false;

  void _trace(String phase, {String? code, String? detail}) {
    final data = <String, Object?>{
      'event': phase,
      'attempt': _attempt,
      'atUtc': DateTime.now().toUtc().toIso8601String(),
    };
    if (code != null) data['code'] = code;
    if (detail != null) data['detail'] = detail;
    onDiagnostic(data);
  }

  static String _safeText(String message) {
    final safe = message
        .replaceAll(RegExp(r'[a-fA-F0-9]{32}'), '[room-key]')
        .replaceAll(RegExp(r'(?:\d{1,3}\.){3}\d{1,3}'), '[ip-address]')
        .replaceAll(
          RegExp(r'(sdp|candidate)=[^\s&]+', caseSensitive: false),
          '[webrtc-data]',
        );
    return safe.length <= 280 ? safe : '${safe.substring(0, 280)}…';
  }

  /// Independent HTTP probe after a failed socket handshake: shows whether
  /// Cloudflare itself is reachable and whether this room has a ready host.
  /// The room key is used only in the request URL; never copied to diagnostics.
  static Future<void> probeRoom(
    String roomKey, {
    required SignallingTrace onDiagnostic,
    String? serverEndpoint,
  }) async {
    final start = DateTime.now();
    final url = (serverEndpoint ?? endpoint)
        .replaceFirst('wss://', 'https://')
        .replaceFirst('ws://', 'http://');
    final target = Uri.parse('${url}status/$roomKey');
    try {
      final response = await http
          .get(target, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      Object? state, hostSockets, pendingGuests, protocol;
      if (response.statusCode == 200) {
        try {
          final value = jsonDecode(response.body);
          if (value is Map<String, dynamic>) {
            state = switch (value['state']) {
              'host_ready' => 'host_ready',
              'host_connecting' => 'host_connecting',
              'host_absent' => 'host_absent',
              _ => 'unrecognized',
            };
            hostSockets = value['hostSocketCount'] is int
                ? value['hostSocketCount']
                : null;
            pendingGuests = value['pendingGuests'] is int
                ? value['pendingGuests']
                : null;
            protocol = value['protocol'] is int ? value['protocol'] : null;
          }
        } on FormatException {
          state = 'invalid_json';
        }
      }
      final edge = response.headers['cf-ray'];
      final data = <String, Object?>{
        'event': 'http_probe',
        'atUtc': DateTime.now().toUtc().toIso8601String(),
        'httpStatus': response.statusCode,
        'elapsedMs': elapsed,
      };
      if (state != null) data['roomState'] = state;
      if (hostSockets != null) data['hostSockets'] = hostSockets;
      if (pendingGuests != null) data['guestSockets'] = pendingGuests;
      if (protocol != null) data['serverProtocol'] = protocol;
      if (edge != null && RegExp(r'^[A-Za-z0-9-]{5,60}$').hasMatch(edge)) {
        data['cloudflareRay'] = edge;
      }
      onDiagnostic(data);
    } on Object catch (error) {
      onDiagnostic({
        'event': 'http_probe_failed',
        'atUtc': DateTime.now().toUtc().toIso8601String(),
        'errorType': '${error.runtimeType}',
        'detail': _safeText('$error'),
      });
    }
  }

  static Future<P2pSignalling> connect(
    String roomKey, {
    required bool host,
    required void Function(Map<String, dynamic>) onMessage,
    required void Function(String) onError,
    required SignallingTrace onDiagnostic,
    String? serverEndpoint,
  }) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(roomKey)) {
      throw const FormatException('Invalid online room key.');
    }
    final role = host ? 'host' : 'guest';
    Object? lastFailure;
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (attempt > 1) {
        await Future<void>.delayed(Duration(milliseconds: 450 * (attempt - 1)));
      }
      onDiagnostic({
        'event': 'connect_attempt',
        'atUtc': DateTime.now().toUtc().toIso8601String(),
        'role': role,
        'attempt': attempt,
      });
      final stopwatch = Stopwatch()..start();
      WebSocketChannel channel;
      try {
        channel = WebSocketChannel.connect(
          Uri.parse('${serverEndpoint ?? endpoint}$roomKey?role=$role'),
        );
      } on Object catch (error) {
        lastFailure = error;
        onDiagnostic({
          'event': 'socket_creation_failed',
          'attempt': attempt,
          'errorType': '${error.runtimeType}',
          'detail': _safeText('$error'),
        });
        continue;
      }
      final client = P2pSignalling._(
        channel,
        onMessage,
        onError,
        onDiagnostic,
        attempt,
      );
      try {
        await Future.wait<void>([channel.ready, client._ready.future])
            .timeout(const Duration(seconds: 7));
        onDiagnostic({
          'event': 'connected',
          'atUtc': DateTime.now().toUtc().toIso8601String(),
          'attempt': attempt,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        });
        return client;
      } on Object catch (error) {
        stopwatch.stop();
        await client.dispose();
        onDiagnostic({
          'event': 'connect_attempt_failed',
          'atUtc': DateTime.now().toUtc().toIso8601String(),
          'attempt': attempt,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'errorType': '${error.runtimeType}',
          'detail': _safeText('$error'),
        });
        if (error is StateError &&
            !error.message.toString().contains('before joining')) {
          await probeRoom(
            roomKey,
            onDiagnostic: onDiagnostic,
            serverEndpoint: serverEndpoint,
          );
          rethrow;
        }
        lastFailure = error;
      }
    }
    await probeRoom(
      roomKey,
      onDiagnostic: onDiagnostic,
      serverEndpoint: serverEndpoint,
    );
    onDiagnostic({
      'event': 'connect_exhausted',
      'atUtc': DateTime.now().toUtc().toIso8601String(),
      'attempts': 3,
      'lastErrorType': '${lastFailure.runtimeType}',
      if (lastFailure != null) 'lastDetail': _safeText('$lastFailure'),
    });
    throw StateError(
      'Could not establish WebSocket signalling after 3 attempts. '
      'Check the copied connection diagnostics for the server HTTP probe. '
      'Manual pairing remains available.',
    );
  }

  void send(Map<String, dynamic> message) {
    if (!_closed) _channel.sink.add(jsonEncode(message));
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    await _subscription.cancel();
    await _channel.sink.close();
  }
}
