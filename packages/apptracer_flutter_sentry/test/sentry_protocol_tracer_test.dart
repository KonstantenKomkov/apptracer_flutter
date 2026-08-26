import 'dart:convert';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:apptracer_flutter_sentry/apptracer_flutter_sentry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _dsn = 'https://key@tracer.example.ru/42';

TracerEvent _event({String message = 'could not parse the response'}) =>
    TracerEvent(
      exceptionType: 'FormatException',
      message: message,
      stackTrace: DartStackTrace.parse('#0      main (package:x/x.dart:1:2)'),
    );

void main() {
  late List<http.Request> sent;

  MockClient client({int status = 200, Map<String, String>? headers}) {
    sent = <http.Request>[];
    return MockClient((http.Request request) async {
      sent.add(request);
      return http.Response('', status, headers: headers ?? const {});
    });
  }

  test('stays disabled without a DSN', () async {
    final SentryProtocolTracer tracer =
        SentryProtocolTracer(httpClient: client());

    await tracer.initialize(const TracerOptions());

    expect(tracer.isEnabled, isFalse);
  });

  test('stays disabled on a malformed DSN rather than swallowing events',
      () async {
    final SentryProtocolTracer tracer =
        SentryProtocolTracer(httpClient: client());

    await tracer.initialize(const TracerOptions(dsn: 'nonsense'));

    expect(tracer.isEnabled, isFalse);
  });

  test('posts an envelope to the DSN with the auth header', () async {
    final MockClient mock = client();
    final SentryProtocolTracer tracer = SentryProtocolTracer(httpClient: mock);
    await tracer.initialize(const TracerOptions(dsn: _dsn));

    await tracer.recordError(_event());

    expect(sent, hasLength(1));
    final http.Request request = sent.single;
    expect(
        request.url.toString(), 'https://tracer.example.ru/api/42/envelope/');
    expect(request.headers['Content-Type'], 'application/x-sentry-envelope');
    expect(request.headers['X-Sentry-Auth'], contains('sentry_key=key'));
    expect(request.headers['X-Sentry-Auth'], contains('sentry_version=7'));
  });

  test('the item header counts bytes, not characters', () async {
    // A message outside ASCII makes the two differ, and an ingest reading the
    // wrong number of bytes rejects the whole envelope.
    final MockClient mock = client();
    final SentryProtocolTracer tracer = SentryProtocolTracer(httpClient: mock);
    await tracer.initialize(const TracerOptions(dsn: _dsn));

    await tracer.recordError(_event(message: 'не удалось разобрать ответ'));

    final List<String> lines = sent.single.body.split('\n');
    final Map<String, Object?> itemHeader =
        jsonDecode(lines[1]) as Map<String, Object?>;
    expect(itemHeader['type'], 'event');
    expect(itemHeader['length'], utf8.encode(lines[2]).length);
    expect(itemHeader['length'], greaterThan(lines[2].length));
  });

  test('the envelope header repeats the event id', () async {
    final MockClient mock = client();
    final SentryProtocolTracer tracer = SentryProtocolTracer(httpClient: mock);
    await tracer.initialize(const TracerOptions(dsn: _dsn));

    await tracer.recordError(_event());

    final List<String> lines = sent.single.body.split('\n');
    final String headerId =
        (jsonDecode(lines[0]) as Map<String, Object?>)['event_id']! as String;
    final String bodyId =
        (jsonDecode(lines[2]) as Map<String, Object?>)['event_id']! as String;
    expect(headerId, bodyId);
    expect(headerId, hasLength(32));
  });

  test('a 429 mutes the transport instead of hammering the ingest', () async {
    final MockClient mock =
        client(status: 429, headers: <String, String>{'retry-after': '120'});
    final SentryProtocolTracer tracer = SentryProtocolTracer(httpClient: mock);
    await tracer.initialize(const TracerOptions(dsn: _dsn));

    await tracer.recordError(_event());
    await tracer.recordError(_event());

    expect(sent, hasLength(1), reason: 'the second event must not be sent');
  });

  test('a failing ingest never propagates into the application', () async {
    final MockClient mock = MockClient((_) async => throw StateError('down'));
    final SentryProtocolTracer tracer = SentryProtocolTracer(httpClient: mock);
    await tracer.initialize(const TracerOptions(dsn: _dsn));

    await expectLater(tracer.recordError(_event()), completes);
  });

  test('sends nothing after stopCollection', () async {
    final MockClient mock = client();
    final SentryProtocolTracer tracer = SentryProtocolTracer(httpClient: mock);
    await tracer.initialize(const TracerOptions(dsn: _dsn));

    await tracer.stopCollection();
    await tracer.recordError(_event());

    expect(sent, isEmpty);
    expect(tracer.isEnabled, isFalse);
  });
}
