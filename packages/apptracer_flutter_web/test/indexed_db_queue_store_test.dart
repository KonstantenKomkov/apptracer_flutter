@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:apptracer_flutter_web/apptracer_flutter_web.dart';
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
  _Client(this.offline);
  final bool offline;
  final List<String> bodies = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    if (offline) throw http.ClientException('offline');
    return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('{}')), 200);
  }
}

TracerHttpTracer _tracer(
  _Client client,
  TracerQueueStore store, {
  Duration initialBackoff = const Duration(milliseconds: 5),
}) {
  return TracerHttpTracer(
    facts: const _Facts(),
    sdkVersion: 'test',
    httpClient: client,
    queueStore: store,
    deliveryPolicy: TracerDeliveryPolicy(
      initialBackoff: initialBackoff,
      requestTimeout: const Duration(milliseconds: 50),
    ),
  );
}

TracerEvent _event() => TracerEvent(
      exceptionType: 'StateError',
      message: 'indexed-db-reload',
      stackTrace:
          DartStackTrace.parse('#0 main (package:example/main.dart:1:1)'),
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  test('IndexedDB snapshot survives another store instance and clears',
      () async {
    final name = 'apptracer-test-${DateTime.now().microsecondsSinceEpoch}';
    final first = IndexedDbQueueStore(databaseName: name);
    final record = <String, Object?>{'id': 'one', 'payload': '[]'};
    await first.save(<TracerQueueRecord>[record]);

    final second = IndexedDbQueueStore(databaseName: name);
    expect(await second.load(), [record]);
    await second.clear();
    expect(await first.load(), isEmpty);
  });

  test('real browser queue restores after reload and never after revoke',
      () async {
    final name = 'apptracer-test-${DateTime.now().microsecondsSinceEpoch}';
    final store = IndexedDbQueueStore(databaseName: name);
    final offlineClient = _Client(true);
    final first =
        _tracer(offlineClient, store, initialBackoff: const Duration(hours: 1));
    await first.startCollection(const TracerOptions(appToken: 'test'));
    await first.recordError(_event());
    expect(
        (await store.load()).single['payload'], contains('indexed-db-reload'));

    final persisted = await store.load();
    persisted.single['nextAttemptAt'] = 0;
    await store.save(persisted);
    final onlineClient = _Client(false);
    final reloaded =
        _tracer(onlineClient, IndexedDbQueueStore(databaseName: name));
    await reloaded.startCollection(const TracerOptions(appToken: 'test'));
    await settle();
    expect(onlineClient.bodies.single, offlineClient.bodies.first);
    expect(await store.load(), isEmpty);

    final pending = first.recordError(_event());
    await settle();
    await first.stopAndClearCollection();
    await pending;
    expect(await store.load(), isEmpty);
    final afterRevoke = _Client(false);
    final revoked =
        _tracer(afterRevoke, IndexedDbQueueStore(databaseName: name));
    await revoked.startCollection(const TracerOptions(appToken: 'test'));
    await settle();
    expect(afterRevoke.bodies, isEmpty);
  });
}
