import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/network/p2p_signalling.dart';

void main() {
  const roomKey = '0123456789abcdef0123456789abcdef';

  Future<HttpServer> startServer({
    required bool rejectUpgradeWithHttp,
    String? socketError,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path.startsWith('/signal/status/')) {
        request.response.headers.contentType = ContentType.json;
        request.response.headers.add('CF-Ray', 'abc001-AKL');
        request.response.write(
          jsonEncode({
            'protocol': 2,
            'state': 'host_ready',
            'hostSocketCount': 1,
            'pendingGuests': 0,
          }),
        );
        await request.response.close();
        return;
      }
      if (rejectUpgradeWithHttp) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(request);
      ws.add(
        jsonEncode({
          'op': 'error',
          'code': 'room_full',
          'message': socketError ?? 'Room is full',
        }),
      );
      await ws.close();
    });
    return server;
  }

  test(
    'HTTP 503 WebSocket failure preserves attempts and host evidence',
    () async {
      final server = await startServer(rejectUpgradeWithHttp: true);
      addTearDown(() => server.close(force: true));
      final events = <Map<String, Object?>>[];
      final endpoint = 'ws://127.0.0.1:${server.port}/signal/';
      await expectLater(
        P2pSignalling.connect(
          roomKey,
          host: false,
          onMessage: (_) {},
          onError: (_) {},
          onDiagnostic: events.add,
          serverEndpoint: endpoint,
        ),
        throwsStateError,
      );
      expect(events.where((e) => e['event'] == 'connect_attempt').length, 3);
      expect(
        events.where((e) => e['event'] == 'connect_attempt_failed').length,
        3,
      );
      final probe = events.singleWhere((e) => e['event'] == 'http_probe');
      expect(probe['httpStatus'], 200);
      expect(probe['roomState'], 'host_ready');
      expect(probe['hostSockets'], 1);
      expect(probe['serverProtocol'], 2);
      expect(probe['cloudflareRay'], 'abc001-AKL');
      expect(jsonEncode(events), isNot(contains(roomKey)));
    },
  );

  test('server refusal includes rejection code and redacts secrets', () async {
    final server = await startServer(
      rejectUpgradeWithHttp: false,
      socketError: 'Room $roomKey 10.22.33.44 is full',
    );
    addTearDown(() => server.close(force: true));
    final events = <Map<String, Object?>>[];
    final endpoint = 'ws://127.0.0.1:${server.port}/signal/';
    await expectLater(
      P2pSignalling.connect(
        roomKey,
        host: false,
        onMessage: (_) {},
        onError: (_) {},
        onDiagnostic: events.add,
        serverEndpoint: endpoint,
      ),
      throwsStateError,
    );
    expect(
      events.any(
        (e) => e['event'] == 'server_rejection' && e['code'] == 'room_full',
      ),
      isTrue,
    );
    expect(events.any((e) => e['event'] == 'http_probe'), isTrue);
    final report = jsonEncode(events);
    expect(report, isNot(contains(roomKey)));
    expect(report, isNot(contains('10.22.33.44')));
    expect(report, contains('[room-key]'));
    expect(report, contains('[ip-address]'));
  });
}
