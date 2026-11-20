class LanHostServer {
  int get port =>
      throw UnsupportedError('Cannot host a TCP server in a browser.');
  static Future<LanHostServer> start({
    String bindAddress = '0.0.0.0',
    int port = 0,
    bool advertise = true,
  }) => Future.error(
    UnsupportedError('Host LAN games from the Android or Linux app.'),
  );
  static Future<List<String>> localAddresses() async => [];
  static Future<List<LanFoundRoom>> discover({
    Duration duration = const Duration(milliseconds: 1200),
  }) async => [];
  Future<void> close() async {}
}

class LanFoundRoom {
  const LanFoundRoom(
    this.address,
    this.port,
    this.code,
    this.players,
    this.capacity,
  );
  final String address, code;
  final int port, players, capacity;
  String get invite => '$address:$port/$code';
  String get url => 'ws://$address:$port/room';
}
