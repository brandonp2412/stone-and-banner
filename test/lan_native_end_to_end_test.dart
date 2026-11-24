import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/network/lan_client.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/lan_host.dart';

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 120; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('LAN host/client never reached expected state');
}

void main() {
  test(
    'in-app LAN host accepts real TCP clients, starts match, syncs state',
    () async {
      final server = await LanHostServer.start(
        bindAddress: '127.0.0.1',
        advertise: false,
      );
      final clients = [LanRoomClient(), LanRoomClient(), LanRoomClient()];
      addTearDown(() async {
        for (final client in clients) {
          client.dispose();
        }
        await server.close();
      });
      final url = 'ws://127.0.0.1:${server.port}/room';
      clients[0].host(url, 'Alice', 3, 42);
      await until(() => clients[0].room != null);
      final code = clients[0].room!;
      clients[1].join(url, 'Bob', code);
      clients[2].join(url, 'Carol', code);
      await until(() => clients.every((client) => client.players.length == 3));
      expect(clients.map((client) => client.seat).toList(), [0, 1, 2]);
      expect(clients[0].connectedPlayers, [true, true, true]);
      clients[0].start();
      await until(() => clients.every((client) => client.game != null));
      expect(clients[0].game!.board.tiles.length, 19);
      expect(clients[1].game!.board.tiles, clients[0].game!.board.tiles);
      expect(clients[2].game!.players.length, 3);
    },
  );

  test('LAN host can fill empty seats with the existing AI and play', () async {
    final server = await LanHostServer.start(
      bindAddress: '127.0.0.1',
      advertise: false,
      shuffleTurns: false,
    );
    final host = LanRoomClient();
    addTearDown(() async {
      host.dispose();
      await server.close();
    });
    host.host('ws://127.0.0.1:${server.port}/room', 'Host', 3, 47);
    await until(() => host.room != null);
    host.setBots(2);
    await until(() => host.botCount == 2);
    host.start();
    await until(() => host.game != null);
    expect(host.players.length, 3);
    expect(host.botSeats, [1, 2]);
    host.dispatch(PlaceVillage(MatchEngine.legalVertices(host.game!).first));
    await until(() => host.version == 1 && !host.pending);
    host.dispatch(PlaceRoad(MatchEngine.legalEdges(host.game!).first));
    await until(() => host.version >= 4);
    expect(host.game!.events.length, greaterThanOrEqualTo(0));
    expect(host.error, isNull);
  });
  test('LAN clock survives same-turn moves and reconnects', () async {
    final server = await LanHostServer.start(
      bindAddress: '127.0.0.1',
      advertise: false,
      shuffleTurns: false,
    );
    final host = LanRoomClient();
    final guest = LanRoomClient();
    final recovered = LanRoomClient();
    addTearDown(() async {
      host.dispose();
      guest.dispose();
      recovered.dispose();
      await server.close();
    });
    final url = 'ws://127.0.0.1:${server.port}/room';
    host.host(url, 'Alice', 3, 42);
    await until(() => host.room != null);
    guest.join(url, 'Bob', host.room!);
    await until(() => host.players.length == 2 && guest.token != null);
    host.setBots(1);
    await until(() => host.botCount == 1);
    host.start();
    await until(() => guest.game != null && host.game != null);
    expect(host.turnSecondsRemaining, inInclusiveRange(88, 90));
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    final before = host.turnSecondsRemaining!;
    expect(before, lessThan(89));
    host.dispatch(PlaceVillage(MatchEngine.legalVertices(host.game!).first));
    await until(() => host.version == 1 && guest.version == 1);
    expect(host.turnSecondsRemaining!, lessThanOrEqualTo(before));
    recovered.resume(url, host.room!, guest.token!);
    await until(() => recovered.game != null && recovered.seat == 1);
    expect(recovered.turnSecondsRemaining!, lessThan(89));
    expect(
      (recovered.turnSecondsRemaining! - host.turnSecondsRemaining!).abs(),
      lessThanOrEqualTo(1),
    );
    expect(recovered.game!.sites.keys, guest.game!.sites.keys);
    for (final key in guest.game!.sites.keys) {
      expect(recovered.game!.sites[key]!.owner, guest.game!.sites[key]!.owner);
      expect(
        recovered.game!.sites[key]!.structure,
        guest.game!.sites[key]!.structure,
      );
    }
    host.dispatch(PlaceRoad(MatchEngine.legalEdges(host.game!).first));
    await until(() => host.version == 2 && recovered.version == 2);
    expect(recovered.turnSecondsRemaining, inInclusiveRange(88, 90));
  });
}
