import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Usage: dart run tool/lan_join_probe.dart SERVER_URL ROOM');
  }
  for (final name in ['Ben', 'Cora']) {
    final socket = await WebSocket.connect(args[0]);
    final welcome = socket.firstWhere(
      (item) => (jsonDecode(item as String) as Map)['op'] == 'welcome',
    );
    socket.add(jsonEncode({'op': 'join', 'room': args[1], 'name': name}));
    final result = jsonDecode((await welcome) as String) as Map;
    stdout.writeln('Joined $name to ${result['room']} seat ${result['seat']}');
    await socket.close();
  }
}
