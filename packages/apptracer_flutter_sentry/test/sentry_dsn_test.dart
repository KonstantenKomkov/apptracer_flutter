import 'package:apptracer_flutter_sentry/apptracer_flutter_sentry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SentryDsn.parse', () {
    test('splits a DSN into key, origin and project', () {
      final SentryDsn dsn =
          SentryDsn.parse('https://abc123@tracer.example.ru/42');

      expect(dsn.publicKey, 'abc123');
      expect(dsn.uri.host, 'tracer.example.ru');
      expect(dsn.projectId, '42');
      expect(
        dsn.envelopeUri.toString(),
        'https://tracer.example.ru/api/42/envelope/',
      );
    });

    test('keeps a path prefix, which a self-hosted ingest may have', () {
      final SentryDsn dsn = SentryDsn.parse('https://key@host.ru/prefix/7');

      expect(dsn.projectId, '7');
      expect(dsn.envelopeUri.path, '/prefix/api/7/envelope/');
    });

    test('keeps an explicit port', () {
      final SentryDsn dsn = SentryDsn.parse('http://key@localhost:9000/1');

      expect(
          dsn.envelopeUri.toString(), 'http://localhost:9000/api/1/envelope/');
    });

    test('a secret in the DSN is ignored, only the public key is used', () {
      expect(
        SentryDsn.parse('https://public:secret@host.ru/1').publicKey,
        'public',
      );
    });

    group('refuses what cannot work, rather than swallowing events', () {
      // A mistyped DSN that quietly disabled reporting is the worst outcome
      // here: nothing arrives and nothing says why.
      for (final String bad in <String>[
        'not a dsn',
        'https://host.ru/42',
        'https://key@host.ru',
        '',
      ]) {
        test('"$bad"', () {
          expect(() => SentryDsn.parse(bad), throwsFormatException);
        });
      }
    });
  });
}
