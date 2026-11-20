import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/network/p2p_room.dart';

void main() {
  test('diagnostics include state without leaking peer addresses', () async {
    final room = P2pRoom();
    addTearDown(room.dispose);
    room.host('Alice', 3, 42);
    final result = await room.diagnosticReport(
      uiError: 'Could not reach 192.168.1.10 on the Wi-Fi network',
    );
    final report = jsonDecode(result) as Map<String, dynamic>;
    expect(report['app'], 'Stone & Banner');
    expect(report['role'], 'host');
    expect(report['protocol'], 'WebRTC');
    expect(report['peers'], isEmpty);
    expect((report['status'] as Map)['roomCreated'], true);
    expect(result, contains('host lobby created'));
    expect(result, contains('[IPv4 redacted]'));
    expect(result, isNot(contains('192.168.1.10')));
  });
}
