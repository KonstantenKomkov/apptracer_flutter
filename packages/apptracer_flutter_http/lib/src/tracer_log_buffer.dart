import 'dart:convert';

/// The log Tracer ships as `logsFile` on a web event.
///
/// Every row is `#<index> <epoch millis> | <message>`, newline terminated, and
/// the whole buffer is capped at 64 000 bytes with the oldest rows dropped
/// first. Read on 2026-08-27 from `LogsData` in `@apptracer/sdk` 2.6.9, down to
/// the row format, because the console's log table parses it: a row it cannot
/// read makes it abandon the whole table with `Match line error, expected
/// format: #0 timestamp | text`.
class TracerLogBuffer {
  /// Creates a buffer.
  ///
  /// [now] exists so a test can pin the timestamps; nothing else should pass it.
  TracerLogBuffer({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The vendor's cap, in bytes of UTF-8.
  static const int maxBytes = 64000;

  final DateTime Function() _now;
  final List<String> _rows = <String>[];
  final List<int> _rowBytes = <int>[];
  int _index = 0;
  int _totalBytes = 0;

  /// Appends one row.
  void add(String message) {
    final String row = '#$_index ${_now().millisecondsSinceEpoch} | $message\n';
    final int bytes = utf8.encode(row).length;
    _rows.add(row);
    _rowBytes.add(bytes);
    _totalBytes += bytes;
    _index++;
    // The newest row is never dropped, however long it is: a verbatim stack
    // trace on its own can exceed the cap, and losing it would defeat the
    // point of attaching it. The vendor's loop keeps the last row too.
    while (_totalBytes > maxBytes && _rows.length > 1) {
      _totalBytes -= _rowBytes.removeAt(0);
      _rows.removeAt(0);
    }
  }

  /// The buffer as the wire wants it, or `null` when nothing has been logged.
  ///
  /// The vendor omits the field entirely rather than sending an empty string.
  String? encode() {
    if (_rows.isEmpty) {
      return null;
    }
    return base64Encode(utf8.encode(_rows.join()));
  }

  /// The rows as they would be encoded, for tests and for debugging.
  String get text => _rows.join();
}
