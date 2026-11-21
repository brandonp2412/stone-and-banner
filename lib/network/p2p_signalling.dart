import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Ephemeral SDP exchange via a Cloudflare Durable Object. The Worker never
/// relays gameplay and never stores SDP, match history, or player resources.
class P2pSignalling {
  P2pSignalling._(this._channel, this.onMessage, this.onError) {
    _subscription = _channel.stream.listen(
      (event) {
        try {
          if (event is! String || event.length > 20000) return;
          final message = jsonDecode(event);
          if (message is! Map<String, dynamic>) return;
          if (message['op'] == 'ready') {
            if (!_ready.isCompleted) _ready.complete();
          } else if (!_closed) {
            onMessage(message);
          }
        } on Object catch (error) {
          if (!_closed) onError('Invalid signalling response: $error');
        }
      },
      onError: (Object error) {
        if (!_ready.isCompleted) _ready.completeError(error);
        if (!_closed) onError('Signalling disconnected: $error');
      },
      onDone: () {
        if (!_ready.isCompleted) {
          _ready.completeError(StateError('Signalling closed before joining.'));
        }
        if (!_closed) onError('Signalling connection closed.');
      },
      cancelOnError: false,
    );
  }

  // Enabled by default for production releases now that the free signalling
  // Worker is deployed. Unit tests and debug runs stay offline by default.
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
  final Completer<void> _ready = Completer<void>();
  late final StreamSubscription<dynamic> _subscription;
  bool _closed = false;

  static Future<P2pSignalling> connect(
    String roomKey, {
    required bool host,
    required void Function(Map<String, dynamic>) onMessage,
    required void Function(String) onError,
  }) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(roomKey)) {
      throw const FormatException('Invalid online room key.');
    }
    final role = host ? 'host' : 'guest';
    final channel = WebSocketChannel.connect(
      Uri.parse('$endpoint$roomKey?role=$role'),
    );
    final client = P2pSignalling._(channel, onMessage, onError);
    try {
      // Subscribe to both immediately: a failed handshake can reject the
      // socket and the server-ready event in the same microtask.
      await Future.wait<void>([channel.ready, client._ready.future])
          .timeout(const Duration(seconds: 8));
      return client;
    } on Object {
      await client.dispose();
      rethrow;
    }
  }

  void send(Map<String, dynamic> message) {
    if (!_closed) _channel.sink.add(jsonEncode(message));
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _channel.sink.close();
  }
}
