/// Browser-only RTCPeerConnection bridge.
class P2pTransport {
  static String? initialLink() => null;
  static Map<String, String>? guestSession() => null;
  static void rememberGuestSession(String key, String name, String token) {}
  static void clearGuestSession() {}
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
  void listenAnswers(void Function(String link, String receiptId) callback) {}
  void dispose() {}
  static Future<bool> forwardAnswer(String message) async => false;
  static void acknowledgeAnswer(String id, bool accepted) {}
  static void setHosting(bool hosting) {}
}
