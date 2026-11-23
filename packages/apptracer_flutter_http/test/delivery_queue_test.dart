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

typedef _Plan = Future<http.StreamedResponse> Function();

class _Client extends http.BaseClient {
  _Client(this.plans);
  final List<_Plan> plans;
  final List<String> bodies = <String>[];
  int active = 0;
  int maxActive = 0;
  int calls = 0;
  final requests = <http.BaseRequest>[];

  static _Plan status(int code, {Map<String, String> headers = const {}}) {
    return () async => http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('{}')), code,
        headers: headers);
  }

  static _Plan networkError() =>
      () async => throw http.ClientException('offline');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    ++calls;
    ++active;
    if (active > maxActive) maxActive = active;
    try {
      if (plans.isEmpty) return await status(200)();
      return await plans.removeAt(0)();
    } finally {
      --active;
    }
  }
}

class _Clock {
  DateTime now = DateTime.utc(2026, 1, 1);
  final List<Duration> delays = <Duration>[];
  final List<Completer<void>> completers = <Completer<void>>[];

  final transitions = StreamController<TracerDeliveryState>.broadcast();
  final scheduled = Completer<void>();

  DateTime call() => now;

  Future<void> record(TracerHttpTracer tracer, String message,
      [TracerDeliveryState outcome = TracerDeliveryState.retry]) async {
    final done = transitions.stream.firstWhere((state) => state == outcome);
    await tracer.recordError(_event(message));
    await done;
    if (outcome == TracerDeliveryState.retry) await scheduled.future;
  }

  Future<void> delay(Duration duration) {
    delays.add(duration);
    if (!scheduled.isCompleted) scheduled.complete();
    final completer = Completer<void>();
    completers.add(completer);
    return completer.future;
  }

  Future<void> fireNext(
      [TracerDeliveryState? outcome = TracerDeliveryState.sent]) async {
    await scheduled.future;
    final done = outcome == null
        ? null
        : transitions.stream.firstWhere((state) => state == outcome);
    now = now.add(delays[delays.length - completers.length]);
    // A Timer fires on the event queue, after the pump's current microtasks.
    await Future<void>(() => completers.removeAt(0).complete());
    await done;
  }
}

class _DeniedStore implements TracerQueueStore {
  @override
  Future<List<TracerQueueRecord>> load() => throw StateError('denied');
  @override
  Future<void> save(List<TracerQueueRecord> records) =>
      throw StateError('denied');
  @override
  Future<void> clear() => throw StateError('denied');
}

class _BlockedStore extends TracerMemoryQueueStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool rejectClear = false;

  @override
  Future<void> save(List<TracerQueueRecord> records) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await super.save(records);
  }

  @override
  Future<void> clear() async {
    if (rejectClear) throw StateError('denied');
    await super.clear();
  }
}

const _options = TracerOptions(appToken: 'test-token');
const _policy = TracerDeliveryPolicy(
  requestTimeout: Duration(seconds: 10),
  initialBackoff: Duration(seconds: 1),
  maxBackoff: Duration(seconds: 30),
);

TracerEvent _event(String message) => TracerEvent(
      exceptionType: 'StateError',
      message: message,
      stackTrace:
          DartStackTrace.parse('#0 main (package:example/main.dart:1:1)'),
    );

TracerHttpTracer _tracer(
  _Client client,
  TracerQueueStore store,
  _Clock clock,
  List<TracerDeliveryDiagnostic> diagnostics, {
  TracerDeliveryPolicy? policy,
}) {
  return TracerHttpTracer(
    facts: const _Facts(),
    sdkVersion: 'test',
    httpClient: client,
    queueStore: store,
    deliveryPolicy: policy ?? _policy,
    deliveryListener: (event) {
      diagnostics.add(event);
      clock.transitions.add(event.state);
    },
    clock: clock.call,
    random: () => 1,
    delay: clock.delay,
  );
}

void main() {
  test('offline event persists and the same bytes are delivered after retry',
      () async {
    final client = _Client([_Client.networkError(), _Client.status(200)]);
    final store = TracerMemoryQueueStore();
    final clock = _Clock();
    final diagnostics = <TracerDeliveryDiagnostic>[];
    final tracer = _tracer(client, store, clock, diagnostics);
    await tracer.startCollection(_options);

    await clock.record(tracer, 'offline');
    expect(store.records, hasLength(1));
    expect(clock.delays, [const Duration(seconds: 1)]);
    expect(
        diagnostics.map((value) => value.state),
        containsAll(<TracerDeliveryState>[
          TracerDeliveryState.queued,
          TracerDeliveryState.retry
        ]));

    await clock.fireNext();
    expect(client.calls, 2);
    expect(client.bodies[0], client.bodies[1]);
    expect(store.records, isEmpty);
    expect(client.maxActive, 1);
    expect(diagnostics.last.state, TracerDeliveryState.sent);
  });

  test('an authorized reload restores the queue without a manual recordError',
      () async {
    final firstClient = _Client([_Client.networkError()]);
    final store = TracerMemoryQueueStore();
    final clock = _Clock();
    final first = _tracer(firstClient, store, clock, []);
    await first.startCollection(_options);
    await clock.record(first, 'before reload');

    final secondClient = _Client([]);
    final secondClock = _Clock()..now = clock.now;
    final second = _tracer(secondClient, store, secondClock, []);
    await second.startCollection(_options);
    await secondClock.fireNext();

    expect(secondClient.calls, 1);
    expect(secondClient.bodies.single, firstClient.bodies.single);
    expect(store.records, isEmpty);
  });

  test('request timeout is retryable and permanent 4xx is dropped', () async {
    final timeout = Completer<http.StreamedResponse>();
    final client = _Client([
      () => timeout.future,
      _Client.status(200),
      _Client.status(400),
      _Client.status(200),
    ]);
    final store = TracerMemoryQueueStore();
    final clock = _Clock();
    final diagnostics = <TracerDeliveryDiagnostic>[];
    final tracer = _tracer(client, store, clock, diagnostics,
        policy: const TracerDeliveryPolicy(
            requestTimeout: Duration(milliseconds: 5)));
    await tracer.startCollection(_options);

    await clock.record(tracer, 'timeout');
    expect(diagnostics.map((value) => value.state),
        contains(TracerDeliveryState.retry));
    await clock.fireNext();
    await clock.record(tracer, 'bad request', TracerDeliveryState.dropped);

    expect(client.calls, 3);
    expect(
        diagnostics.any((value) =>
            value.state == TracerDeliveryState.dropped &&
            value.reason == 'http_400'),
        isTrue);
    expect(store.records, isEmpty);
    timeout.completeError(StateError('late response must not affect the test'));
  });

  test('429 uses Retry-After instead of a tight loop', () async {
    final client = _Client([
      _Client.status(429, headers: const {'retry-after': '7'}),
      _Client.status(200),
    ]);
    final clock = _Clock();
    final tracer = _tracer(client, TracerMemoryQueueStore(), clock, []);
    await tracer.startCollection(_options);
    await clock.record(tracer, 'rate limited');

    expect(clock.delays, [const Duration(seconds: 7)]);
    expect(client.calls, 1);
    await clock.fireNext();
    expect(client.calls, 2);
  });

  test('TTL and malformed records are discarded during restore', () async {
    final store = TracerMemoryQueueStore();
    store.records = <TracerQueueRecord>[
      <String, Object?>{'broken': true},
    ];
    final firstClient = _Client([_Client.networkError()]);
    final clock = _Clock();
    final diagnostics = <TracerDeliveryDiagnostic>[];
    final first = _tracer(firstClient, store, clock, diagnostics,
        policy: const TracerDeliveryPolicy(timeToLive: Duration(seconds: 1)));
    await first.startCollection(_options);
    expect(
        diagnostics.any((value) => value.reason == 'malformed_record'), isTrue);
    await clock.record(first, 'expired');

    clock.now = clock.now.add(const Duration(seconds: 2));
    final secondClient = _Client([]);
    final second = _tracer(secondClient, store, clock, diagnostics,
        policy: const TracerDeliveryPolicy(timeToLive: Duration(seconds: 1)));
    await second.startCollection(_options);

    expect(secondClient.calls, 0);
    expect(store.records, isEmpty);
    expect(diagnostics.any((value) => value.reason == 'ttl_expired'), isTrue);
  });

  test('queue overflow drops the oldest event and stays within the count limit',
      () async {
    final client =
        _Client(List<_Plan>.generate(3, (_) => _Client.networkError()));
    final store = TracerMemoryQueueStore();
    final clock = _Clock();
    final diagnostics = <TracerDeliveryDiagnostic>[];
    final tracer = _tracer(client, store, clock, diagnostics,
        policy: const TracerDeliveryPolicy(maxEntries: 2));
    await tracer.startCollection(_options);

    final pending = <Future<void>>[
      tracer.recordError(_event('first')),
      tracer.recordError(_event('second')),
      tracer.recordError(_event('third')),
    ];

    await Future.wait(pending);
    expect(store.records, hasLength(2));
    expect(store.records[0]['payload'], contains('second'));
    expect(store.records[1]['payload'], contains('third'));
    expect(
        diagnostics.any((value) => value.reason == 'queue_overflow'), isTrue);
    await tracer.stopAndClearCollection();
  });

  test('stop clear removes the queue and late retry cannot restore it',
      () async {
    final client = _Client([_Client.networkError()]);
    final store = TracerMemoryQueueStore();
    final clock = _Clock();
    final tracer = _tracer(client, store, clock, []);
    await tracer.startCollection(_options);
    await clock.record(tracer, 'revoked');
    await tracer.stopAndClearCollection();
    expect(store.records, isEmpty);

    await clock.fireNext(null);
    await tracer.startCollection(_options);
    expect(client.calls, 1);
    expect(store.records, isEmpty);
  });

  test('denied persistence is diagnosed and memory delivery continues',
      () async {
    final client = _Client([]);
    final diagnostics = <TracerDeliveryDiagnostic>[];
    final clock = _Clock();
    final tracer = _tracer(client, _DeniedStore(), clock, diagnostics);
    await tracer.startCollection(_options);
    await clock.record(tracer, 'memory only', TracerDeliveryState.sent);

    expect(client.calls, 1);
    expect(
        diagnostics.any((value) =>
            value.state == TracerDeliveryState.failed &&
            value.reason == 'storage_unavailable'),
        isTrue);
    expect(diagnostics.any((value) => value.reason == 'memory_only'), isTrue);
  });
  test('clear orders a pending save before a concurrent restart', () async {
    final store = _BlockedStore();
    final client = _Client([]);
    final clock = _Clock();
    final tracer = _tracer(client, store, clock, []);
    await tracer.startCollection(_options);
    final recording = tracer.recordError(_event('revoked'));
    await store.entered.future;
    final stopping = tracer.stopAndClearCollection();
    expect(tracer.isEnabled, isFalse);
    final restarting = tracer.startCollection(_options);
    store.release.complete();
    expect((await stopping).state, TracerCollectionState.disabled);
    expect((await restarting).isEnabled, isTrue);
    await recording;
    expect(store.records, isEmpty);
    expect(client.calls, 0);
    await clock.record(tracer, 'fresh', TracerDeliveryState.sent);
    expect(client.bodies.single, contains('fresh'));
  });

  test('a save interrupted by an account change stays in its original session',
      () async {
    final store = _BlockedStore();
    final previous = <TracerDeliveryDiagnostic>[];
    final current = <TracerDeliveryDiagnostic>[];
    final client = _Client([]);
    final tracer = _tracer(client, store, _Clock(), []);
    await tracer
        .startCollection(_options.copyWith(deliveryListener: previous.add));
    final recording = tracer.recordError(_event('private account A payload'));
    await store.entered.future;
    final sent = Completer<void>();
    final next = TracerOptions(
        appToken: 'second-token',
        deliveryListener: (event) {
          current.add(event);
          if (event.state == TracerDeliveryState.sent) sent.complete();
        });
    tracer.configureDelivery(next);
    expect(tracer.isEnabled, isFalse);
    final restarting = tracer.startCollection(next);
    store.release.complete();
    await recording;
    await restarting;
    await tracer.recordError(_event('account B'));
    await sent.future;
    expect(previous, isEmpty);
    expect(current.map((event) => event.reason),
        ['account_mismatch', 'persisted', 'http_200']);
    expect(client.requests.single.url.queryParameters['crashToken'],
        'second-token');
    expect(client.bodies.single, isNot(contains('account A')));
  });

  test('failed cleanup is reported and retried before restore', () async {
    final store = _BlockedStore()..release.complete();
    final client = _Client([_Client.networkError()]);
    final clock = _Clock();
    final tracer = _tracer(client, store, clock, []);
    await tracer.startCollection(_options);
    await clock.record(tracer, 'revoked');
    store.rejectClear = true;
    expect((await tracer.stopAndClearCollection()).state,
        TracerCollectionState.error);
    expect((await tracer.startCollection(_options)).state,
        TracerCollectionState.error);
    store.rejectClear = false;
    expect((await tracer.startCollection(_options)).isEnabled, isTrue);
    expect(store.records, isEmpty);
    expect(client.calls, 1);
  });

  test('HTTP-date Retry-After and TTL are honored in an open page', () async {
    for (final ttl in [3, 30]) {
      final clock = _Clock();
      final client = _Client([
        _Client.status(429,
            headers: {'retry-after': 'Thu, 01 Jan 2026 00:00:07 GMT'}),
      ]);
      final store = TracerMemoryQueueStore();
      final diagnostics = <TracerDeliveryDiagnostic>[];
      final tracer = _tracer(client, store, clock, diagnostics,
          policy: TracerDeliveryPolicy(timeToLive: Duration(seconds: ttl)));
      await tracer.startCollection(_options);
      await clock.record(tracer, 'rate limited');
      expect(clock.delays.single, Duration(seconds: ttl == 3 ? 3 : 7));
      await clock.fireNext(
          ttl == 3 ? TracerDeliveryState.dropped : TracerDeliveryState.sent);
      expect(client.calls, ttl == 3 ? 1 : 2);
      expect(store.records, isEmpty);
      if (ttl == 3) expect(diagnostics.last.reason, 'ttl_expired');
    }
  });

  test(
      'restore enforces queue limits and isolates tokens with the same legacy hash',
      () async {
    final store = TracerMemoryQueueStore();
    final clock = _Clock();
    final first = _tracer(_Client([_Client.networkError()]), store, clock, []);
    await first.startCollection(const TracerOptions(appToken: 'Aa'));
    await clock.record(first, 'before reload');
    final record = store.records.single;
    store.records = [
      for (var i = 0; i < 3; i++) {...record, 'id': 'id-$i'}
    ];
    final secondClient = _Client([]);
    final second = _tracer(secondClient, store, clock, [],
        policy: const TracerDeliveryPolicy(maxEntries: 1));
    await second.startCollection(const TracerOptions(appToken: 'Aa'));
    expect(store.records.single['id'], 'id-2');
    await second.startCollection(const TracerOptions(appToken: 'BB'));
    expect(store.records, isEmpty);
    expect(secondClient.calls, 0);
  });

  test('timeout signals abort and retries keep the ingest contract', () async {
    final client = _Client([]);
    final cancelled = Completer<void>();
    client.plans.add(() async {
      await (client.requests.single as http.Abortable).abortTrigger;
      cancelled.complete();
      throw http.ClientException('aborted');
    });
    final clock = _Clock();
    final tracer = _tracer(client, TracerMemoryQueueStore(), clock, [],
        policy: const TracerDeliveryPolicy(
            requestTimeout: Duration(milliseconds: 5)));
    await tracer.startCollection(
        const TracerOptions(appToken: 'test', apiUrl: 'http://example.org'));
    await clock.record(tracer, 'vendor contract');
    await cancelled.future;
    await clock.fireNext();
    expect(client.maxActive, 1);
    for (final request in client.requests) {
      expect(request.method, 'POST');
      expect(request.url.scheme, 'https');
      expect(request.url.path, '/api/crash/uploadBatch');
      expect(request.url.queryParameters, {
        'crashToken': 'test',
        'compressType': 'NONE',
        'sdkVersion': 'test',
      });
      expect(request.headers['content-type'], 'application/octet-stream');
    }
    final item = (jsonDecode(client.bodies.first) as List).single;
    expect(
        item.keys,
        containsAll(
            ['type', 'format', 'severity', 'uploadBean', 'stackTrace']));
    expect(item['format'], 'JS_STACKTRACE');
  });
  test('reload during the last attempt cannot reset its budget', () async {
    final response = Completer<http.StreamedResponse>();
    final entered = Completer<void>();
    final store = TracerMemoryQueueStore();
    final clock = _Clock();
    const policy = TracerDeliveryPolicy(maxAttempts: 1);
    final first = _tracer(
        _Client([
          () {
            entered.complete();
            return response.future;
          }
        ]),
        store,
        clock,
        [],
        policy: policy);
    await first.startCollection(_options);
    final pending = first.recordError(_event('in flight'));
    await entered.future;
    expect(store.records.single['attempts'], 1);
    final client = _Client([]);
    final restored = _tracer(client, store, clock, [], policy: policy);
    await restored.startCollection(_options);
    expect(client.calls, 0);
    expect(store.records, isEmpty);
    response.complete(await _Client.status(200)());
    await pending;
  });

  test(
      'options listener supersedes the legacy listener without duplicate events',
      () async {
    final legacy = <TracerDeliveryDiagnostic>[];
    final current = <TracerDeliveryDiagnostic>[];
    final sent = Completer<void>();
    final tracer =
        _tracer(_Client([]), TracerMemoryQueueStore(), _Clock(), legacy);
    await tracer.startCollection(
      _options.copyWith(deliveryListener: (event) {
        current.add(event);
        if (event.state == TracerDeliveryState.sent) sent.complete();
        throw StateError('private listener exception');
      }),
    );

    await tracer.recordError(_event('diagnostic metadata'));
    await sent.future;

    expect(current.map((event) => event.reason), ['persisted', 'http_200']);
    expect(current.map((event) => event.attempt), [0, 1]);
    expect(legacy, isEmpty);
    expect(current.map((event) => event.state),
        [TracerDeliveryState.queued, TracerDeliveryState.sent]);
    expect(current.map((event) => event.backend).toSet(), {'tracer-http'});
    expect(current.map((event) => event.operation).toSet(), {'delivery'});
  });
}
