/// Browser-only RTCPeerConnection bridge.
class P2pTransport {
  static String? initialLink() => null;
  P2pTransport(this.onEvent);
  final void Function(String peer, String event, String data) onEvent;

  Future<String> offer(String id) =>
      Future.error(UnsupportedError('Browser only.'));
  Future<String> answer(String id, String offer) =>
      Future.error(UnsupportedError('Browser only.'));
  Future<void> accept(String id, String answer) =>
      Future.error(UnsupportedError('Browser only.'));
  void send(String id, String message) =>
      throw UnsupportedError('Browser only.');
  void close(String id) {}
  void listenAnswers(void Function(String) callback) {}
  void dispose() {}
  static void broadcastAnswer(String message) {}
}
