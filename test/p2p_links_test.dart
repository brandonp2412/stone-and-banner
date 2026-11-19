import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/network/p2p_links.dart';

void main() {
  final base = Uri.parse('https://brandonp2412.github.io/stone-and-banner/');
  final offer = {
    'type': 'offer',
    'room': 'AABBCCDD',
    'peer': '0123456789abcdef01234567',
    'sdp': '{"type":"offer","sdp":"v=0\\r\\na=ice-ufrag:abc\\r\\n"}',
  };

  test('manual offer encodes as opaque fragment without query', () {
    final link = P2pLinks.link(base, offer);
    final uri = Uri.parse(link);
    expect(uri.query, isEmpty);
    expect(uri.path, '/stone-and-banner/');
    expect(
      link,
      isNot(contains('?#p2p=')),
      reason: 'The host must not reload when a response opens in its tab.',
    );
    expect(link, contains('/stone-and-banner/#p2p='));
    expect(uri.fragment, startsWith('p2p='));
    expect(P2pLinks.parse(link), {'v': 1, ...offer});
  });

  test('existing host query parameters survive offer and response', () {
    final tracked = Uri.parse('$base?qa=1');
    final link = P2pLinks.link(tracked, offer);
    expect(Uri.parse(link).query, 'qa=1');
    expect(P2pLinks.parse(link), {'v': 1, ...offer});
  });

  test('manual response link round-trips SDP and Unicode', () {
    final payload = {...offer, 'type': 'answer', 'sdp': '✓ ice candidate'};
    expect(P2pLinks.parse(P2pLinks.link(base, payload)), {'v': 1, ...payload});
  });

  test('non-invitation and invalid versions are rejected', () {
    expect(() => P2pLinks.parse('https://example.org/'), throwsFormatException);
    expect(() => P2pLinks.parse(''), throwsFormatException);
    final wrong = P2pLinks.link(base, {...offer, 'v': 99});
    expect(() => P2pLinks.parse(wrong), throwsFormatException);
  });

  test('oversized and malformed payloads are rejected', () {
    expect(() => P2pLinks.parse('x' * 30001), throwsFormatException);
    expect(
      () => P2pLinks.parse('https://example.org/#p2p=%%%'),
      throwsFormatException,
    );
    final bad = P2pLinks.link(base, {...offer, 'room': 'bad'});
    expect(() => P2pLinks.parse(bad), throwsFormatException);
  });
}
