import 'dart:convert';

/// ICE descriptions travel in URL fragments, not HTTP requests to Pages.
abstract final class P2pLinks {
  static String link(Uri origin, Map<String, dynamic> message) {
    final encoded = base64Url
        .encode(utf8.encode(jsonEncode({'v': 1, ...message})))
        .replaceAll('=', '');
    // Keep the same document URL so that opening a response in the original
    // host tab changes only the fragment, never reloading the live room.
    return Uri(
      scheme: origin.scheme,
      userInfo: origin.userInfo,
      host: origin.host,
      port: origin.hasPort ? origin.port : null,
      path: origin.path,
      query: origin.query.isEmpty ? null : origin.query,
      fragment: 'p2p=$encoded',
    ).toString();
  }

  static Map<String, dynamic> parse(String input) {
    final value = input.trim();
    if (value.isEmpty || value.length > 30000) {
      throw const FormatException('Invalid or oversized P2P link.');
    }
    // Native WebSocket LAN invites cannot be opened from a GitHub Pages
    // browser. Reject them immediately instead of showing 'Connecting'.
    if (RegExp(
      r'^(?:(?:ws|wss|https?)://)?\d{1,3}(?:\.\d{1,3}){3}:\d+/(?:[0-9a-fA-F]{8}|room(?:/.*)?)$',
    ).hasMatch(value)) {
      throw const FormatException(
        'That is a native-app LAN invite. It cannot connect to a browser. '
        'On the host, open Multiplayer → Host game, then share the '
        'WebRTC invitation link instead.',
      );
    }
    final fragment = Uri.tryParse(value)?.fragment ?? '';
    final raw = fragment.startsWith('p2p=')
        ? fragment.substring(4)
        : value.startsWith('p2p=')
        ? value.substring(4)
        : '';
    if (raw.isEmpty) {
      throw const FormatException('Not a Stone & Banner P2P link.');
    }
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(raw))),
    );
    if (payload is! Map<String, dynamic> ||
        payload['v'] != 1 ||
        !['offer', 'answer'].contains(payload['type']) ||
        payload['room'] is! String ||
        (payload['room'] as String).length != 8 ||
        payload['peer'] is! String ||
        (payload['peer'] as String).length < 12 ||
        payload['sdp'] is! String ||
        (payload['sdp'] as String).length > 18000) {
      throw const FormatException('Invalid P2P link payload.');
    }
    return payload;
  }
}
