import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Encrypted WebRTC DataChannel transport for Linux and Android.
/// Uses manual SDP offer/answer links, direct ICE or free capped TURN relay.
/// No hosted gameplay state or persistent signalling server is involved.
class P2pTransport {
  P2pTransport(this.onEvent);

  // flutter_webrtc defaults to receiving audio and video even for a
  // DataChannel-only game. Suppress unused media sections to keep manual
  // invitation URLs short and avoid negotiating unnecessary tracks.
  static const _dataOnlySdpConstraints = <String, dynamic>{
    'mandatory': <String, dynamic>{
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': <dynamic>[],
  };

  static const _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];
  static final Uri _relayConfigUrl = Uri.parse(
    'https://stone-banner-turn.brandonp2412.workers.dev/ice',
  );

  // The free relay's credential stays in a Worker secret, not the APK or Git.
  // On quota exhaustion we still allow direct LAN/STUN connections and explain
  // that WAN reliability is degraded in the copied ICE diagnostics.
  static Future<List<Map<String, dynamic>>> _relayServers() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .getUrl(_relayConfigUrl)
          .timeout(const Duration(seconds: 7));
      final response = await request.close().timeout(
        const Duration(seconds: 7),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'Free relay unavailable (HTTP ${response.statusCode}).',
        );
      }
      final raw = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 7));
      final payload = jsonDecode(raw);
      if (payload is! Map || payload['iceServers'] is! List) {
        throw const FormatException('Invalid free relay configuration.');
      }
      final servers = <Map<String, dynamic>>[];
      for (final item in payload['iceServers'] as List) {
        if (item is! Map || item['urls'] is! String) continue;
        servers.add(Map<String, dynamic>.from(item));
      }
      if (!servers.any((item) => (item['urls'] as String).startsWith('turn'))) {
        throw const FormatException('No TURN servers were configured.');
      }
      return servers;
    } finally {
      client.close(force: true);
    }
  }

  final void Function(String peer, String event, String data) onEvent;
  final Map<String, _NativePeer> _peers = {};
  bool _disposed = false;

  static String? initialLink() => null;
  static Future<bool> forwardAnswer(String message) async => false;
  static void acknowledgeAnswer(String id, bool accepted) {}
  static void setHosting(bool hosting) {}

  // Native applications receive links by pasting them into the lobby.
  void listenAnswers(void Function(String link, String receiptId) callback) {}

  void _signal(String id, String kind, [String data = '']) {
    if (!_disposed && _peers.containsKey(id)) onEvent(id, kind, data);
  }

  void _attach(String id, RTCDataChannel channel) {
    final peer = _peers[id];
    if (peer == null) {
      unawaited(channel.close());
      return;
    }
    peer.channel = channel;
    var reportedOpen = false;
    void report(RTCDataChannelState state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen && !reportedOpen) {
        reportedOpen = true;
        _signal(id, 'open');
        _signal(
          id,
          'path',
          'Encrypted WebRTC established; check ICE candidate types for route.',
        );
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _signal(id, 'close');
      }
    }

    channel.onDataChannelState = report;
    channel.onMessage = (message) {
      if (!message.isBinary && message.text.length <= 131072) {
        _signal(id, 'message', message.text);
      }
    };
    if (channel.state != null) report(channel.state!);
  }

  Future<_NativePeer> _create(String id, bool host) async {
    if (_disposed || _peers.containsKey(id)) {
      throw StateError('Peer already exists or transport was disposed.');
    }
    var servers = <Map<String, dynamic>>[..._iceServers];
    String? relayError;
    try {
      servers = await _relayServers();
    } on Object catch (error) {
      relayError = error.toString();
    }
    final connection = await createPeerConnection({
      'iceServers': servers,
      'iceTransportPolicy': 'all',
    });
    final peer = _NativePeer(connection);
    _peers[id] = peer;
    peer.relayConfigured = relayError == null;
    peer.relayConfigError = relayError;
    if (relayError != null) {
      _signal(
        id,
        'diagnostic',
        'Free TURN relay unavailable; direct paths only: $relayError',
      );
    }

    connection.onDataChannel = (channel) => _attach(id, channel);
    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _signal(
          id,
          'error',
          'WebRTC ICE failed; check local UDP and candidate discovery. '
              'Copy diagnostics to investigate; this is not necessarily NAT.',
        );
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _signal(id, 'close');
      }
    };
    connection.onIceConnectionState = (state) {
      _signal(id, 'ice', state.toString());
    };
    connection.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !peer.gathered.isCompleted) {
        peer.gathered.complete();
      }
    };
    connection.onIceCandidate = (candidate) {
      final text = candidate.candidate ?? '';
      if ((text.contains(' typ relay') ||
              (!peer.relayConfigured &&
                  (text.contains(' typ srflx') ||
                      text.contains(' typ prflx')))) &&
          peer.publicCandidateTimer == null) {
        peer.publicCandidateTimer = Timer(const Duration(seconds: 1), () {
          if (!peer.gathered.isCompleted) peer.gathered.complete();
        });
      }
    };
    if (host) {
      final channel = await connection.createDataChannel(
        'stone-banner',
        RTCDataChannelInit()..ordered = true,
      );
      _attach(id, channel);
    }
    return peer;
  }

  Future<String> _localDescription(String id, _NativePeer peer) async {
    // Non-trickle manual signalling: wait for local (and, when available,
    // STUN-reflexive) ICE candidates to appear in the returned SDP.
    await peer.gathered.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {},
    );
    peer.publicCandidateTimer?.cancel();
    final description = await peer.connection.getLocalDescription();
    if (description == null || description.sdp == null) {
      throw StateError('Could not gather WebRTC connection details.');
    }
    final sdp = description.sdp!;
    final hasRelay = sdp.contains(' typ relay');
    final hasPublic = sdp.contains(' typ srflx') || sdp.contains(' typ prflx');
    final hasHost = sdp.contains(' typ host');
    _signal(
      id,
      'diagnostic',
      hasRelay
          ? 'TURN relay candidate gathered; WAN path can traverse carrier NAT.'
          : hasPublic
          ? 'Public STUN candidate found; direct internet connection can be attempted.'
          : hasHost
          ? 'Only local candidates available; direct internet connection may fail.'
          : 'No ICE candidates found; check network connectivity.',
    );
    // This subnet is reserved for device-control WireGuard. WebRTC may
    // discover it as a host interface, but gameplay must never traverse it.
    final gameSdp = sdp
        .split(RegExp(r'\r?\n'))
        .where(
          (line) =>
              !line.startsWith('a=candidate:') ||
              !RegExp(r' 10\.66\.66\.\d+ ').hasMatch(line),
        )
        .join('\r\n');
    return jsonEncode({'type': description.type, 'sdp': gameSdp});
  }

  Future<String> offer(String id) async {
    final peer = await _create(id, true);
    try {
      final offer = await peer.connection.createOffer(_dataOnlySdpConstraints);
      await peer.connection.setLocalDescription(offer);
      return await _localDescription(id, peer);
    } catch (_) {
      close(id);
      rethrow;
    }
  }

  Future<String> answer(String id, String remote) async {
    final description = _decode(remote, 'offer');
    final peer = await _create(id, false);
    try {
      await peer.connection.setRemoteDescription(description);
      final answer = await peer.connection.createAnswer(
        _dataOnlySdpConstraints,
      );
      await peer.connection.setLocalDescription(answer);
      return await _localDescription(id, peer);
    } catch (_) {
      close(id);
      rethrow;
    }
  }

  Future<void> accept(String id, String answer) async {
    final peer = _peers[id];
    if (peer == null) throw StateError('Invitation expired or replaced.');
    await peer.connection.setRemoteDescription(_decode(answer, 'answer'));
  }

  RTCSessionDescription _decode(String raw, String expected) {
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['type'] != expected ||
        data['sdp'] is! String ||
        (data['sdp'] as String).length > 18000) {
      throw FormatException('Invalid WebRTC $expected.');
    }
    return RTCSessionDescription(data['sdp'] as String, expected);
  }

  static List<Map<String, Object>> _candidateDetails(String? sdp) {
    if (sdp == null) return [];
    return [
      for (final row in sdp.split(RegExp(r'\r?\n')))
        if (row.startsWith('a=candidate:')) _candidateDetail(row),
    ];
  }

  static Map<String, Object> _candidateDetail(String row) {
    final words = row.split(RegExp(r'\s+'));
    final typeIndex = words.indexOf('typ');
    final address = words.length > 4 ? words[4] : '';
    final parts = address.split('.');
    final privateIp =
        parts.length == 4 &&
        (parts[0] == '10' ||
            parts[0] == '192' && parts[1] == '168' ||
            parts[0] == '172' &&
                (int.tryParse(parts[1]) ?? 0) >= 16 &&
                (int.tryParse(parts[1]) ?? 0) <= 31);
    return {
      'type': typeIndex >= 0 && typeIndex + 1 < words.length
          ? words[typeIndex + 1]
          : 'unknown',
      'protocol': words.length > 2 ? words[2].toLowerCase() : 'unknown',
      'family': address.endsWith('.local')
          ? 'mDNS'
          : address.contains(':')
          ? 'IPv6'
          : 'IPv4',
      'mdns': address.endsWith('.local'),
      'privateIPv4': privateIp,
    };
  }

  /// Redacted WebRTC diagnostics for support. Never include raw SDP/IP/ICE keys.
  Future<String> diagnostics(String id) async {
    final peer = _peers[id];
    if (peer == null) {
      return jsonEncode({'status': 'no active peer connection'});
    }
    final connection = peer.connection;
    final local = await connection.getLocalDescription();
    final remote = await connection.getRemoteDescription();
    return jsonEncode({
      'engine': 'flutter_webrtc native',
      'relayConfigured': peer.relayConfigured,
      'relayConfigError': peer.relayConfigError,
      'iceConnectionState':
          connection.iceConnectionState?.toString() ?? 'unknown',
      'iceGatheringState':
          connection.iceGatheringState?.toString() ?? 'unknown',
      'signalingState': connection.signalingState?.toString() ?? 'unknown',
      'connectionState': connection.connectionState?.toString() ?? 'unknown',
      'dataChannelState': peer.channel?.state?.toString() ?? 'not created',
      'localDescription': local?.type ?? 'none',
      'remoteDescription': remote?.type ?? 'none',
      'localCandidates': _candidateDetails(local?.sdp),
      'remoteCandidates': _candidateDetails(remote?.sdp),
    });
  }

  void send(String id, String message) {
    final channel = _peers[id]?.channel;
    if (channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Peer not connected.');
    }
    unawaited(
      channel!.send(RTCDataChannelMessage(message)).catchError((Object e) {
        _signal(id, 'error', 'Could not send peer message: $e');
      }),
    );
  }

  void close(String id) {
    final peer = _peers.remove(id);
    if (peer == null) return;
    peer.publicCandidateTimer?.cancel();
    if (!peer.gathered.isCompleted) peer.gathered.complete();
    unawaited(peer.channel?.close());
    unawaited(peer.connection.close());
  }

  void dispose() {
    _disposed = true;
    for (final id in _peers.keys.toList()) {
      close(id);
    }
  }
}

class _NativePeer {
  _NativePeer(this.connection);
  final RTCPeerConnection connection;
  final Completer<void> gathered = Completer<void>();
  RTCDataChannel? channel;
  Timer? publicCandidateTimer;
  bool relayConfigured = false;
  String? relayConfigError;
}
