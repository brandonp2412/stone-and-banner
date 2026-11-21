import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/network/room_protocol.dart';
import 'package:stone_and_banner/network/room_store.dart';

void main() {
  late Directory directory;
  late LanRoomStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('stone-lan-store-test-');
    store = LanRoomStore(directory);
  });
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('rejects a broad checkpoint directory before changing its mode', () {
    expect(
      () => LanRoomStore(Directory.current).load(),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('lobby seats and tokens survive host restart, all disconnected', () {
    final registry = store.load();
    final room = registry.create(3, 42, 'Ada');
    room.join('Ben');
    room.seats[0].connected = true;
    store.save(room);
    final recovered = LanRoomStore(directory).load().find(room.id);
    expect(recovered.state, isNull);
    expect(recovered.seats.map((s) => s.name), ['Ada', 'Ben']);
    expect(recovered.seats.map((s) => s.token), room.seats.map((s) => s.token));
    expect(recovered.seats.every((s) => !s.connected), true);
    recovered.join('Cora');
    recovered.start(0);
    expect(recovered.state!.players.length, 3);
  });

  test('replay, hidden state, dedupe, rejection, and next move restore', () {
    final registry = store.load();
    final room = registry.create(3, 42, 'Ada')
      ..join('Ben')
      ..join('Cora');
    room.start(0);
    final first = PlaceVillage(MatchEngine.legalVertices(room.state!).first);
    final action = first.toJson();
    final ack = room.move(0, 'accept-1', 0, action);
    expect(ack['ok'], true);
    expect(room.move(1, 'reject-1', 1, action)['ok'], false);
    store.save(room);

    final recovered = LanRoomStore(directory).load().find(room.id);
    expect(recovered.secretSeed, room.secretSeed);
    expect(
      MatchEngine.snapshot(recovered.state!),
      MatchEngine.snapshot(room.state!),
    );
    expect(recovered.version, 1);
    expect(recovered.seatFor(room.seats[1].token), 1);
    expect(recovered.historyAfter(0), room.historyAfter(0));
    expect(recovered.move(0, 'accept-1', 0, action), ack);
    expect(recovered.version, 1);
    expect(
      recovered.move(0, 'accept-1', 0, const EndTurn().toJson())['ok'],
      false,
    );
    expect(recovered.move(1, 'reject-1', 1, action)['ok'], false);
    expect(recovered.move(0, 'fresh-stale', 0, action)['ok'], false);
    final second = PlaceRoad(MatchEngine.legalEdges(recovered.state!).first);
    expect(recovered.move(0, 'accept-2', 1, second.toJson())['ok'], true);
    store.save(recovered);
    final next = LanRoomStore(directory).load().find(room.id);
    expect(next.version, 2);
    expect(next.state!.active, 1);
    expect(next.historyAfter(1).single['kind'], 'road');
    expect(
      MatchEngine.snapshot(next.replayOnHost()),
      MatchEngine.snapshot(next.state!),
    );
    final guestView = RoomProtocol.view(next.state!, 1);
    expect(guestView['seed'], 0);
    expect(guestView['events'], isEmpty);
    expect(guestView['drawPiles'], isEmpty);
  });

  test('atomic replacement and corrupt checkpoint fail closed', () {
    final registry = store.load();
    final room = registry.create(3, 9, 'Ada');
    store.save(room);
    final checkpoint = File('${directory.path}/${room.id}.json');
    expect(checkpoint.existsSync(), true);
    room.join('Ben');
    store.save(room);
    expect(LanRoomStore(directory).load().find(room.id).seats.length, 2);
    expect(directory.listSync().where((p) => p.path.endsWith('.tmp')), isEmpty);
    checkpoint.writeAsStringSync('{broken');
    expect(
      () => LanRoomStore(directory).load(),
      throwsA(isA<FileSystemException>()),
    );
    // The bad record is never replaced by an empty room.
    expect(checkpoint.readAsStringSync(), '{broken');
  });
}
