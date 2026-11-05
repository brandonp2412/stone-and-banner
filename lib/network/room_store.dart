import 'dart:convert';
import 'dart:io';

import 'room_host.dart';

/// Private, local-disk LAN checkpoints. No cloud, relay or public endpoints.
/// Each room is replaced atomically after a flushed temporary file is written.
class LanRoomStore {
  LanRoomStore(this.directory);

  final Directory directory;
  var _sequence = 0;

  LanRoomRegistry load() {
    final location = directory.absolute.path;
    if (location == '/' ||
        location == Directory.current.absolute.path ||
        location == Platform.environment['HOME']) {
      throw FileSystemException('Refusing broad LAN state directory', location);
    }
    directory.createSync(recursive: true);
    if (Platform.isLinux || Platform.isMacOS) {
      final result = Process.runSync('chmod', ['700', directory.path]);
      if (result.exitCode != 0) {
        throw FileSystemException(
          'Cannot protect LAN state directory',
          directory.path,
        );
      }
    }
    final registry = LanRoomRegistry();
    final files =
        directory
            .listSync(followLinks: false)
            .where((item) => item.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final item in files) {
      if (item is! File || item.lengthSync() > 32 * 1024 * 1024) {
        throw FileSystemException('Unsafe LAN checkpoint', item.path);
      }
      try {
        final data = Map<String, dynamic>.from(
          jsonDecode(item.readAsStringSync()) as Map,
        );
        final room = HostedRoom.fromPrivateJson(data);
        if (item.uri.pathSegments.last != '${room.id}.json') {
          throw const FormatException('LAN room filename mismatch.');
        }
        registry.restore(room);
      } on Object catch (error) {
        throw FileSystemException(
          'Cannot restore LAN checkpoint: $error',
          item.path,
        );
      }
    }
    return registry;
  }

  /// Synchronous on purpose: a success ack is never sent before this returns.
  /// A failed write must terminate the host (never accept unjournaled moves).
  void save(HostedRoom room) {
    final target = File('${directory.path}/${room.id}.json');
    final temp = File('${directory.path}/.${room.id}.$pid.${_sequence++}.tmp');
    try {
      temp.writeAsStringSync(jsonEncode(room.toPrivateJson()), flush: true);
      temp.renameSync(target.path);
    } on Object {
      if (temp.existsSync()) temp.deleteSync();
      rethrow;
    }
  }

  static String defaultPath() {
    final env = Platform.environment;
    final base =
        env['XDG_STATE_HOME'] ??
        '${env['HOME'] ?? Directory.current.path}/.local/state';
    return '$base/stone-and-banner/lan-rooms';
  }
}
