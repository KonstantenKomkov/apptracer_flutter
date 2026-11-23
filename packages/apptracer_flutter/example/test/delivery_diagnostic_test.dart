import 'dart:async';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FailingCleanup extends legacy.TracerMemoryQueueStore {
  @override
  Future<void> clear() async => throw StateError('private storage failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed HTTP cleanup is reported once per lifecycle call', () async {
    final diagnostics = <TracerDeliveryDiagnostic>[];
    final original = TracerPlatform.instance;
    TracerPlatform.instance = legacy.TracerHttpTracer(
        facts: legacy.PlatformClientFacts(),
        sdkVersion: 'test',
        queueStore: _FailingCleanup());
    addTearDown(() => TracerPlatform.instance = original);
    final options =
        TracerOptions(appToken: 'test', deliveryListener: diagnostics.add);
    await Tracer.startCollection(options);
    expect((await Tracer.stopAndClearCollection()).state,
        TracerCollectionState.error);
    expect(diagnostics.single.reason, 'storage_clear_failed');
    expect((await Tracer.startCollection(options)).state,
        TracerCollectionState.error);
    await Tracer.stopCollection();
    expect(diagnostics.map((event) => event.reason),
        List.filled(3, 'storage_clear_failed'));
  });

  test('a queued stop cannot notify the listener of a later start', () async {
    final original = TracerPlatform.instance;
    final first = <TracerDeliveryDiagnostic>[];
    final second = <TracerDeliveryDiagnostic>[];
    TracerPlatform.instance = legacy.TracerHttpTracer(
        facts: legacy.PlatformClientFacts(),
        sdkVersion: 'test',
        queueStore: _FailingCleanup());
    addTearDown(() => TracerPlatform.instance = original);
    await Tracer.startCollection(
        TracerOptions(appToken: 'first', deliveryListener: first.add));
    final stopping = Tracer.stopCollection();
    final starting = Tracer.startCollection(
        TracerOptions(appToken: 'second', deliveryListener: second.add));
    await stopping;
    expect((await starting).state, TracerCollectionState.error);
    expect(first, isEmpty);
    // Only the recovery attempt belongs to the second start.
    expect(second.single.reason, 'storage_clear_failed');
  });

  test('public facade changes HTTP accounts while an upload is in flight',
      () async {
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    final requests = <http.Request>[];
    final network = MockClient((request) async {
      requests.add(request);
      if (!entered.isCompleted) {
        entered.complete();
        return response.future;
      }
      return http.Response('', 204);
    });
    final previous = <legacy.TracerDeliveryDiagnostic>[];
    final current = <TracerDeliveryDiagnostic>[];
    final fallback = <legacy.TracerDeliveryDiagnostic>[];
    final original = TracerPlatform.instance;
    final transport = legacy.TracerHttpTracer(
      facts: legacy.PlatformClientFacts(),
      sdkVersion: 'test',
      httpClient: network,
      deliveryPolicy:
          const legacy.TracerDeliveryPolicy(requestTimeout: Duration(days: 1)),
      deliveryListener: fallback.add,
    );
    TracerPlatform.instance = transport;
    addTearDown(() async {
      if (!response.isCompleted) response.complete(http.Response('', 204));
      await Tracer.stopCollection();
      TracerPlatform.instance = original;
    });
    final legacy.TracerDeliveryListener first = previous.add;
    await Tracer.initialize(
      options: TracerOptions(
          appToken: 'first-token',
          deliveryListener: first,
          captureZoneErrors: false,
          initialCustomKeys: const {'first-key': 'first-value'}),
      appRunner: () {},
    );
    final recorded = Tracer.recordError('first-payload', StackTrace.current);
    await entered.future;
    await recorded;
    expect(response.isCompleted, isFalse);

    final sent = Completer<void>();
    await Tracer.initialize(
      options: TracerOptions(
          appToken: 'second-token',
          captureZoneErrors: false,
          deliveryListener: (event) {
            current.add(event);
            if (event.state == TracerDeliveryState.sent) sent.complete();
          }),
      appRunner: () {},
    );
    response.complete(http.Response('private rejection', 403));
    await Tracer.recordError('second-payload', StackTrace.current);
    await sent.future;
    expect(previous.map((d) => d.state), [legacy.TracerDeliveryState.queued]);
    expect(current.map((d) => d.reason),
        ['account_mismatch', 'persisted', 'http_204']);
    expect(fallback, isEmpty);
    expect(requests.map((r) => r.url.queryParameters['crashToken']),
        ['first-token', 'second-token']);
    expect(requests.last.body, contains('second-payload'));
    expect(requests.last.body, isNot(contains('first-key')));
  });
}
