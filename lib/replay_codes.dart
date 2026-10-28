import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Compact transport for the canonical JSON replay; no game state is changed.
class ReplayCodes {
  static const prefix = 'sbz1:';
  static const maxEncodedLength = 160000;
  static const maxDecodedBytes = 1024 * 1024;

  static String compact(String raw) =>
      prefix + base64Url.encode(gzip.encode(utf8.encode(raw)));

  static String expand(String raw) {
    final input = raw.trim();
    if (!input.startsWith(prefix)) return input;
    if (input.length > maxEncodedLength) {
      throw const FormatException('Replay share code is too large.');
    }
    // Android keyboard injection may use the standard Base64 aliases.
    final encoded = input
        .substring(prefix.length)
        .replaceAll('+', '-')
        .replaceAll('/', '_');
    final compressed = base64Url.decode(base64Url.normalize(encoded));
    final sink = _LimitedBytes(maxDecodedBytes);
    final decoder = gzip.decoder.startChunkedConversion(sink);
    decoder.add(compressed);
    decoder.close();
    return utf8.decode(sink.bytes());
  }
}

class _LimitedBytes implements Sink<List<int>> {
  _LimitedBytes(this.limit);
  final int limit;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _length = 0;
  @override
  void add(List<int> chunk) {
    if (_length + chunk.length > limit) {
      throw const FormatException('Replay exceeds the 1 MB safety limit.');
    }
    _length += chunk.length;
    _buffer.add(chunk);
  }

  @override
  void close() {}

  Uint8List bytes() => _buffer.takeBytes();
}
