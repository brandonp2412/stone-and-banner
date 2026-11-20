import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Direct, encrypted WebRTC DataChannel transport for Linux and Android.
/// Uses the same SDP offer/answer JSON as the browser implementation.
/// No signalling, TURN, account or gameplay server is involved.
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
        _signal(id, 'path', 'Direct encrypted P2P connection established.');
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
    final connection = await createPeerConnection({
      'iceServers': _iceServers,
      'iceTransportPolicy': 'all',
    });
    final peer = _NativePeer(connection);
    _peers[id] = peer;

    connection.onDataChannel = (channel) => _attach(id, channel);
    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _signal(
          id,
          'error',
          'Direct connection failed (NAT/firewall). No relay configured.',
        );
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _signal(id, 'close');
      }
    };
    connection.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !peer.gathered.isCompleted) {
        peer.gathered.complete();
      }
    };
    connection.onIceCandidate = (candidate) {
      final text = candidate.candidate ?? '';
      if ((text.contains(' typ srflx') || text.contains(' typ prflx')) &&
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
      const Duration(seconds: 9),
      onTimeout: () {},
    );
    peer.publicCandidateTimer?.cancel();
    final description = await peer.connection.getLocalDescription();
    if (description == null || description.sdp == null) {
      throw StateError('Could not gather WebRTC connection details.');
    }
    final sdp = description.sdp!;
    final hasPublic = sdp.contains(' typ srflx') || sdp.contains(' typ prflx');
    final hasHost = sdp.contains(' typ host');
    _signal(
      id,
      'diagnostic',
      hasPublic
          ? 'Public STUN candidate found; direct internet connection can be attempted.'
          : hasHost
          ? 'Only local candidates available; direct internet connection may fail.'
          : 'No ICE candidates found; check network connectivity.',
    );
    return jsonEncode({'type': description.type, 'sdp': sdp});
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
}
