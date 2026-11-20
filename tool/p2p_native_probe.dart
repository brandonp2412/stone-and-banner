// Manual native WebRTC end-to-end probe for both guest and host roles.
// Guest: flutter build linux --release -t tool/p2p_native_probe.dart
// Host: same build with --dart-define=STONE_PROBE_HOST=true
// Files under /tmp/stone-p2p-* are exchanged manually with the Android app.
// Run on an isolated display; never unlock the real desktop for this test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stone_and_banner/network/p2p_links.dart';
import 'package:stone_and_banner/network/p2p_room.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Native WebRTC probe'))),
    ),
  );
  const hostMode = bool.fromEnvironment('STONE_PROBE_HOST');
  final room = P2pRoom();
  final stateFile = File('/tmp/stone-p2p-linux-state.json');
  void report([String? failure]) {
    final obj = <String, Object?>{
      'ready': hostMode ? room.invitationLink != null : room.answerLink != null,
      'role': hostMode ? 'host' : 'guest',
      'connected': room.connected,
      'roomId': room.roomId,
      'seat': room.seat,
      'started': room.started,
      'version': room.version,
      'players': room.players,
      'message': room.message,
      'diagnostic': room.networkDiagnostic,
      'path': room.connectionPath,
      'failure': failure,
    };
    stateFile.writeAsStringSync(jsonEncode(obj));
    // ignore: avoid_print
    print('P2P_PROBE ${jsonEncode(obj)}');
  }

  room.addListener(report);
  try {
    if (hostMode) {
      room.host('Linux Host', 3, 61942);
      await room.invite();
      if (room.invitationLink == null) {
        throw StateError(room.message ?? 'No invitation SDP');
      }
      await File('/tmp/stone-p2p-offer.txt')
          .writeAsString(room.invitationLink!);
      report();
      final responseFile = File('/tmp/stone-p2p-native-answer.txt');
      for (var i = 0; i < 1200; i++) {
        if (await responseFile.exists()) {
          await room.acceptAnswer(await responseFile.readAsString());
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      for (var i = 0; i < 90; i++) {
        if (room.players.length > 1) {
          room.setBotCount(1);
          if (room.canStart) room.start();
          report();
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } else {
      final offer = await File('/tmp/stone-p2p-offer.txt').readAsString();
      await room.join('Linux Guest', P2pLinks.parse(offer));
      if (room.answerLink == null) {
        throw StateError(room.message ?? 'No response SDP');
      }
      await File('/tmp/stone-p2p-answer.txt').writeAsString(room.answerLink!);
      report();
    }
    for (var i = 0; i < 180; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (i % 10 == 0) report();
    }
  } on Object catch (error, stack) {
    report('$error\n$stack');
  }
}
