import 'dart:io';

import 'package:stone_and_banner/network/lan_host.dart';

/// Optional headless host; the Android/Linux game also hosts LAN natively.
Future<void> main(List<String> args) async {
  var bind = '127.0.0.1', port = 8765;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--bind' && i + 1 < args.length) {
      bind = args[++i];
    } else if (args[i] == '--port' && i + 1 < args.length) {
      port = int.parse(args[++i]);
    } else {
      throw FormatException(
        'Usage: dart run tool/lan_server.dart [--bind LAN_IP] [--port 8765]',
      );
    }
  }
  final host = await LanHostServer.start(
    bindAddress: bind,
    port: port,
    advertise: bind != '127.0.0.1',
  );
  stdout.writeln('Stone & Banner LAN host on $bind:${host.port}');
  await ProcessSignal.sigint.watch().first;
  await host.close();
}
