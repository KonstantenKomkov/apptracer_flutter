import 'dart:async';
import 'dart:convert';

import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Facts extends TracerClientFacts {
  const _Facts();
  @override
  String get deviceId => 'device';
  @override
  String get sessionUuid => 'session';
  @override
  String get host => 'test.invalid';
  @override
  int get screenWidth => 100;
  @override
  int get screenHeight => 100;
  @override
  int get screenOrientationAngle => 0;
  @override
  String get documentVisibilityState => 'visible';
}

class _Client extends http.BaseClient {
  final List<String> bodies = <String>[];
  final Completer<void> entered = Completer<void>();
  Completer<void>? response;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) throw StateError('Client is closed');
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    if (!entered.isCompleted) entered.complete();
    if (response != null) await response!.future;
    return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('{"success":true}')), 200);
  }

  @override
  void close() {
    closed = true;
  }
}

TracerEvent _event(String message) => TracerEvent(
      exceptionType: 'StateError',
      message: message,
      stackTrace:
          DartStackTrace.parse('#0 main (package:example/main.dart:1:1)'),
    );
const _options = TracerOptions(
    appToken: 'test-token',
    nativeInitialization: TracerNativeInitialization.deferred);

void main() {
  test('stop clears account data and ignores all diagnostics while disabled',
      () async {
    final client = _Client();
    final tracer = TracerHttpTracer(
        facts: const _Facts(), sdkVersion: 'test', httpClient: client);
    expect((await tracer.startCollection(_options)).isEnabled, isTrue);
    await tracer.setUserId('ACCOUNT_A');
    await tracer.setCustomKey(key: 'ACCOUNT_A', value: 'old');
    await tracer.recordLog('ACCOUNT_A');
    await tracer.recordError(_event('first'));
    expect((await tracer.stopAndClearCollection()).state,
        TracerCollectionState.disabled);
    expect(client.closed, isFalse); // Caller owns an injected client.
    await tracer.setUserId('OFF_USER');
    await tracer.setCustomKey(key: 'OFF_KEY', value: 'off');
    await tracer.recordLog('OFF_LOG');
    await tracer.recordError(_event('OFF_ERROR'));
    expect(client.bodies, hasLength(1));
    expect((await tracer.startCollection(_options)).isEnabled, isTrue);
    await tracer.setUserId('ACCOUNT_B');
    await tracer.recordLog('ACCOUNT_B');
    await tracer.recordError(_event('second'));
    expect(client.bodies, hasLength(2));
    final body = client.bodies.last;
    expect(body, contains('ACCOUNT_B'));
    expect(body, isNot(contains('ACCOUNT_A')));
    expect(body, isNot(contains('OFF_')));
    final item =
        (jsonDecode(body) as List<dynamic>).single as Map<String, dynamic>;
    final logs = utf8.decode(base64Decode(item['logsFile'] as String));
    expect(logs, contains('ACCOUNT_B'));
    expect(logs, isNot(contains('ACCOUNT_A')));
    expect(logs, isNot(contains('OFF_LOG')));
  });

  test(
      'owned client is recreated after stop and an in-flight response cannot restart collection',
      () async {
    final clients = <_Client>[];
    await http.runWithClient(() async {
      final tracer =
          TracerHttpTracer(facts: const _Facts(), sdkVersion: 'test');
      await tracer.startCollection(_options);
      final first = clients.single;
      first.response = Completer<void>();
      final sending = tracer.recordError(_event('in-flight'));
      await first.entered.future;
      await tracer.stopAndClearCollection();
      expect(first.closed, isTrue);
      first.response!.complete();
      await sending;
      expect(tracer.isEnabled, isFalse);
      await tracer.recordError(_event('after-stop'));
      expect(first.bodies, hasLength(1));
      await tracer.startCollection(_options);
      expect(clients, hasLength(2));
      await tracer.recordError(_event('new-consent'));
      expect(clients.last.bodies, hasLength(1));
      expect(clients.last.closed, isFalse);
      await tracer.stopAndClearCollection();
    }, () {
      final client = _Client();
      clients.add(client);
      return client;
    });
  });

  test('disabled or tokenless start revokes an existing session', () async {
    final client = _Client();
    final tracer = TracerHttpTracer(
        facts: const _Facts(), sdkVersion: 'test', httpClient: client);
    await tracer.startCollection(_options);
    expect((await tracer.startCollection(const TracerOptions())).isEnabled,
        isFalse);
    await tracer.recordError(_event('missing-token'));
    await tracer.startCollection(_options);
    expect(
        (await tracer
                .startCollection(_options.copyWith(isCollectionEnabled: false)))
            .isEnabled,
        isFalse);
    await tracer.recordError(_event('disabled'));
    expect(client.bodies, isEmpty);
  });
}
