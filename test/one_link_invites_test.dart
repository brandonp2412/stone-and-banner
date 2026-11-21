import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/network/p2p_links.dart';

void main() {
  const website = 'https://brandonp2412.github.io/stone-and-banner/';
  const key = '00112233445566778899aabbccddeeff';

  test('one link is reusable and contains no ICE credentials or SDP', () {
    final invite = P2pLinks.roomLink(Uri.parse(website), key);
    expect(invite, startsWith('$website#p2p='));
    expect(invite, isNot(contains('candidate')));
    expect(invite, isNot(contains('sdp')));
    expect(P2pLinks.parse(invite), {'v': 2, 'type': 'room', 'key': key});
    expect(P2pLinks.parse(invite), P2pLinks.parse(invite));
  });

  test('invalid room keys cannot be used', () {
    expect(
      () => P2pLinks.roomLink(Uri.parse(website), '1234'),
      throwsFormatException,
    );
    expect(
      () => P2pLinks.roomLink(Uri.parse(website), 'z' * 32),
      throwsFormatException,
    );
    expect(() => P2pLinks.parse('not-an-invite'), throwsFormatException);
  });

  test('existing manual offer and answer links remain compatible', () {
    for (final type in ['offer', 'answer']) {
      final link = P2pLinks.link(Uri.parse(website), {
        'type': type,
        'room': '1a2b3c4d',
        'peer': '1234567890abcdef12345678',
        'sdp': '{"type":"offer","sdp":"test"}',
      });
      expect(P2pLinks.parse(link)['type'], type);
      expect(P2pLinks.parse(link)['v'], 1);
    }
  });
}
