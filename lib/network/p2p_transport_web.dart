import 'dart:js_interop';

@JS('stoneP2p.initialLink')
external JSString? _initialLink();

@JS('stoneP2p.create')
external void _create(JSString id, JSBoolean isHost, JSFunction callback);
@JS('stoneP2p.offer')
external JSPromise<JSString> _offer(JSString id);
@JS('stoneP2p.answer')
external JSPromise<JSString> _answer(JSString id, JSString remote);
@JS('stoneP2p.accept')
external JSPromise<JSAny?> _accept(JSString id, JSString remote);
@JS('stoneP2p.send')
external void _send(JSString id, JSString message);
@JS('stoneP2p.close')
external void _close(JSString id);
@JS('stoneP2p.onAnswer')
external void _onAnswer(JSFunction callback);
@JS('stoneP2p.offAnswer')
external void _offAnswer(JSFunction callback);
@JS('stoneP2p.postAnswer')
external void _postAnswer(JSString message);

class P2pTransport {
  static String? initialLink() {
    // Flutter's standalone web test harness doesn't load our index.html.
    try {
      return _initialLink()?.toDart;
    } on Object {
      return null;
    }
  }

  P2pTransport(this.onEvent);
  final void Function(String peer, String event, String data) onEvent;
  final Map<String, JSFunction> _listeners = {};
  JSFunction? _answerListener;

  void _register(String id, bool isHost) {
    final listener = ((JSString event, JSString payload) {
      onEvent(id, event.toDart, payload.toDart);
    }).toJS;
    _listeners[id] = listener;
    _create(id.toJS, isHost.toJS, listener);
  }

  Future<String> offer(String id) async {
    _register(id, true);
    return (await _offer(id.toJS).toDart).toDart;
  }

  Future<String> answer(String id, String offer) async {
    _register(id, false);
    return (await _answer(id.toJS, offer.toJS).toDart).toDart;
  }

  Future<void> accept(String id, String answer) async {
    await _accept(id.toJS, answer.toJS).toDart;
  }

  void send(String id, String message) => _send(id.toJS, message.toJS);
  void close(String id) {
    _close(id.toJS);
    _listeners.remove(id);
  }

  void listenAnswers(void Function(String) callback) {
    if (_answerListener != null) _offAnswer(_answerListener!);
    _answerListener = ((JSString raw) => callback(raw.toDart)).toJS;
    _onAnswer(_answerListener!);
  }

  void dispose() {
    if (_answerListener != null) _offAnswer(_answerListener!);
    for (final id in _listeners.keys.toList()) {
      close(id);
    }
  }

  static void broadcastAnswer(String message) => _postAnswer(message.toJS);
}
