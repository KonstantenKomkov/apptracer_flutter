import 'dart:convert';

import 'package:apptracer_flutter_http/src/tracer_log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TracerLogBuffer', () {
    late DateTime clock;
    TracerLogBuffer build() => TracerLogBuffer(now: () => clock);

    setUp(() {
      clock = DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true);
    });

    test('nothing logged means no field at all', () {
      expect(build().encode(), isNull);
    });

    test('a row reads exactly as the console parses it', () {
      // `#<index> <epoch millis> | <message>`, newline terminated. The console
      // hunts for the next `#N` and gives up on the table when a row differs.
      final TracerLogBuffer buffer = build()
        ..add('[info] ui | tapped {screen=home}')
        ..add('second');

      expect(
        buffer.text,
        '#0 1700000000000 | [info] ui | tapped {screen=home}\n'
        '#1 1700000000000 | second\n',
      );
    });

    test('the index keeps counting past the rows that were dropped', () {
      final TracerLogBuffer buffer = build();
      for (int i = 0; i < 100; i++) {
        buffer.add('x' * 2000);
      }

      expect(buffer.text.startsWith('#0 '), isFalse);
      expect(buffer.text.trimRight().endsWith('x' * 10), isTrue);
      expect(buffer.text.contains('#99 '), isTrue);
    });

    test('the buffer stays under the vendor cap, oldest rows first to go', () {
      final TracerLogBuffer buffer = build();
      for (int i = 0; i < 50; i++) {
        buffer.add('row $i ${'y' * 2000}');
      }

      expect(utf8.encode(buffer.text).length, lessThanOrEqualTo(64000));
      expect(buffer.text.contains('row 0 '), isFalse);
      expect(buffer.text.contains('row 49 '), isTrue);
    });

    test('one row larger than the cap survives on its own', () {
      // A verbatim Dart stack trace can be that row, and dropping it would
      // defeat the reason it is attached.
      final TracerLogBuffer buffer = build()..add('z' * 100000);

      expect(utf8.encode(buffer.text).length, greaterThan(64000));
      expect(buffer.encode(), isNotNull);
    });

    test('what is encoded is base64 of exactly those bytes', () {
      final TracerLogBuffer buffer = build()..add('ошибка в пути');

      expect(utf8.decode(base64Decode(buffer.encode()!)), buffer.text);
    });
  });
}
