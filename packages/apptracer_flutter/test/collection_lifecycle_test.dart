import 'dart:async';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

class LifecyclePlatform extends FakeTracerPlatform {
  Completer<void>? starting;
  Completer<void>? stopping;
  int purgeCalls = 0;
  final List<String> operations = [];

  @override
  Future<TracerCollectionResult> startCollection(TracerOptions options) async {
    operations.add('start');
    await starting?.future;
    await initialize(options);
    return TracerCollectionResult(isEnabled
        ? TracerCollectionState.enabled
        : TracerCollectionState.error);
  }

  @override
  Future<TracerCollectionResult> stopAndClearCollection() async {
    operations.add('purge');
    purgeCalls++;
    await stopping?.future;
    await stopCollection();
    keys.clear();
    logs.clear();
    return const TracerCollectionResult(TracerCollectionState.disabled);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LifecyclePlatform platform;
  late TracerClient client;

  setUp(() {
    platform = LifecyclePlatform();
    client =
        TracerClient(platform: platform, bindings: FakeErrorHandlerBindings());
  });

  Future<void> emit() async {
    client.addBreadcrumb(TracerBreadcrumb(message: 'private breadcrumb'));
    await client.setCustomKey(key: 'private key', value: 'private value');
    await client.setUserId('private user');
    await client.recordLog('private log');
    await client.recordError(StateError('private error'), StackTrace.current);
  }

  test('disabled collection retains no events, keys, breadcrumbs or user',
      () async {
    await client.start(const TracerOptions(
      isCollectionEnabled: false,
      initialCustomKeys: {'initial': 'private'},
    ));
    await emit();
    expect(client.breadcrumbs, isEmpty);
    expect(client.customKeys, isEmpty);
    expect(platform.events, isEmpty);
    expect(platform.logs, isEmpty);
    expect(platform.userIds, isEmpty);
    expect(platform.keys, isEmpty);
  });

  test('purge reaches native before any successful start', () async {
    final result = await client.stopAndClearCollection();
    expect(platform.purgeCalls, 1);
    expect(result.state, TracerCollectionState.disabled);
  });

  test('stop revokes Dart permission before native acknowledges', () async {
    await client.startCollection(const TracerOptions());
    await emit();
    platform.stopping = Completer<void>();
    final stopping = client.stopAndClearCollection();
    expect(client.isEnabled, isFalse);
    expect(client.breadcrumbs, isEmpty);
    expect(client.customKeys, isEmpty);
    final count = platform.events.length;
    final users = platform.userIds.length;
    await emit();
    expect(platform.events.length, count);
    expect(platform.userIds.length, users);
    expect(client.customKeys, isEmpty);
    expect(client.breadcrumbs, isEmpty);
    platform.stopping!.complete();
    await stopping;
    expect(platform.logs, isEmpty);
    expect(platform.keys, isEmpty);
  });

  test('late start cannot reenable after stop; stop follows native start',
      () async {
    platform.starting = Completer<void>();
    final started = client.startCollection(const TracerOptions());
    await Future<void>.delayed(Duration.zero);
    final stopped = client.stopAndClearCollection();
    platform.starting!.complete();
    expect((await started).reason, 'superseded');
    await stopped;
    expect(platform.operations, ['start', 'purge']);
    expect(client.isEnabled, isFalse);
    expect(client.hasInstalledHandlers, isFalse);
    expect(platform.isEnabled, isFalse);
  });

  test('start queued before stop is discarded before contacting native',
      () async {
    final started = client.startCollection(const TracerOptions());
    final stopped = client.stopAndClearCollection();
    expect((await started).reason, 'superseded');
    await stopped;
    expect(platform.operations, ['purge']);
  });

  test(
      'restart without new options cannot revive initial keys from old account',
      () async {
    await client.startCollection(const TracerOptions(
      initialCustomKeys: {'account': 'old-account'},
    ));
    expect(platform.keys['account'], 'old-account');
    await client.stopAndClearCollection();
    await client.startCollection();
    expect(client.customKeys, isEmpty);
    expect(platform.keys, isEmpty);
  });

  test('disabled start during native start orders a stop and cannot reenable',
      () async {
    platform.starting = Completer<void>();
    final starting = client.startCollection(const TracerOptions());
    await Future<void>.delayed(Duration.zero);
    final disabled =
        client.startCollection(const TracerOptions(isCollectionEnabled: false));
    platform.starting!.complete();
    expect((await starting).reason, 'superseded');
    await disabled;
    expect(platform.isEnabled, isFalse);
    expect(client.isEnabled, isFalse);
    expect(platform.stopCalls, 1);
  });

  test('repeated start does not initialize a second service', () async {
    await Future.wait([
      client.startCollection(const TracerOptions()),
      client.startCollection(const TracerOptions()),
    ]);
    expect(platform.initializeCalls, 1);
  });

  test('async stack log cannot forward an old event into a new session',
      () async {
    final logPending = Completer<void>();
    final racePlatform = LogRacePlatform(logPending);
    final raceClient = TracerClient(
        platform: racePlatform, bindings: FakeErrorHandlerBindings());
    await raceClient.startCollection(const TracerOptions());
    final event = raceClient.recordError(StateError('old'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    await raceClient.stopAndClearCollection();
    await raceClient.startCollection(const TracerOptions());
    logPending.complete();
    await event;
    expect(racePlatform.events, isEmpty);
  });

  test('deferred bootstrap and explicit starts run appRunner only once',
      () async {
    Tracer.client = client;
    var runs = 0;
    await Tracer.initialize(
      options: const TracerOptions(
          nativeInitialization: TracerNativeInitialization.deferred),
      appRunner: () => runs++,
    );
    expect(platform.operations, isEmpty);
    expect(runs, 1);
    await Tracer.startCollection();
    await Tracer.stopAndClearCollection();
    await Tracer.startCollection();
    expect(runs, 1);
    await client.stop();
  });
}

class LogRacePlatform extends LifecyclePlatform {
  LogRacePlatform(this.pending);
  final Completer<void> pending;

  @override
  Future<void> recordLog(String message) => pending.future;
}
