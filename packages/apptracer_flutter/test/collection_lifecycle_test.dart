import 'dart:async';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

class LifecyclePlatform extends FakeTracerPlatform {
  Completer<void>? starting;
  Completer<void>? stopping;
  Completer<void>? observing;
  bool nativeDisabled = false;
  Completer<void>? resuming;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int purgeCalls = 0;
  final List<String> operations = [];

  @override
  Future<TracerCollectionResult> startCollection(TracerOptions options) async {
    operations.add('start');
    await starting?.future;
    await initialize(options);
    nativeDisabled = false;
    return TracerCollectionResult(isEnabled
        ? TracerCollectionState.enabled
        : TracerCollectionState.error);
  }

  @override
  Future<TracerCollectionResult> pauseCollection() async {
    pauseCalls++;
    await super.stopCollection();
    return const TracerCollectionResult(TracerCollectionState.disabled);
  }

  @override
  Future<TracerCollectionResult> resumeCollection() async {
    resumeCalls++;
    await resuming?.future;
    await super.initialize(const TracerOptions());
    return const TracerCollectionResult(TracerCollectionState.enabled);
  }

  @override
  Future<TracerCollectionResult> getCollectionState() async {
    await observing?.future;
    if (nativeDisabled) {
      return const TracerCollectionResult(TracerCollectionState.disabled,
          reason: 'sdk_runtime_disabled');
    }
    return super.getCollectionState();
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

  test('pause rejects new events and resume preserves the authorized context',
      () async {
    await client.startCollection(const TracerOptions());
    await emit();
    final keys = client.customKeys;
    final breadcrumbs = client.breadcrumbs;
    final events = platform.events.length;
    await client.pauseCollection();
    expect(client.isEnabled, isFalse);
    expect(client.hasInstalledHandlers, isFalse);
    await emit();
    expect(platform.events.length, events);
    expect(client.customKeys, keys);
    expect(client.breadcrumbs, breadcrumbs);
    expect((await client.resumeCollection()).isEnabled, isTrue);
    expect(client.hasInstalledHandlers, isTrue);
    expect(client.customKeys, keys);
    expect(client.breadcrumbs, breadcrumbs);
    expect(platform.purgeCalls, 0);
    await client.stop();
  });

  test('resume never authorizes collection before start or after clear',
      () async {
    expect((await client.resumeCollection()).reason, 'no_live_pause');
    await client.startCollection(const TracerOptions());
    await client.pauseCollection();
    await client.stopAndClearCollection();
    expect((await client.resumeCollection()).reason, 'no_live_pause');
    expect(platform.resumeCalls, 0);
    expect(client.isEnabled, isFalse);
    expect(client.customKeys, isEmpty);
  });

  test('late resume cannot reinstall handlers after revocation', () async {
    await client.startCollection(const TracerOptions());
    await client.pauseCollection();
    platform.resuming = Completer<void>();
    final resumed = client.resumeCollection();
    await Future<void>.delayed(Duration.zero);
    final stopped = client.stopAndClearCollection();
    platform.resuming!.complete();
    expect((await resumed).reason, 'superseded');
    await stopped;
    expect(client.isEnabled, isFalse);
    expect(client.hasInstalledHandlers, isFalse);
  });

  test('pause supersedes a queued start instead of starting native collection',
      () async {
    final started = client.startCollection(const TracerOptions());
    await client.pauseCollection();
    expect((await started).reason, 'superseded');
    expect((await client.resumeCollection()).reason, 'no_live_pause');
    expect(platform.initializeCalls, 0);
  });

  test('older backends explicitly reject pause, resume and diagnostics',
      () async {
    final older = FakeTracerPlatform();
    expect((await older.pauseCollection()).state,
        TracerCollectionState.unsupported);
    expect((await older.resumeCollection()).state,
        TracerCollectionState.unsupported);
    expect((await older.runHeapDump(tag: 'test')).state,
        TracerDiagnosticState.unsupported);
    expect(
        (await older.runDiskUsage()).state, TracerDiagnosticState.unsupported);
    expect((await older.setHeapDumpEnabled(true)).state,
        TracerDiagnosticState.unsupported);
  });

  test('optional diagnostics cannot authorize collection', () async {
    expect((await client.runHeapDump(tag: 'test')).state,
        TracerDiagnosticState.disabled);
    expect((await client.runDiskUsage()).state, TracerDiagnosticState.disabled);
    expect((await client.setHeapDumpEnabled(true)).state,
        TracerDiagnosticState.disabled);
    expect(client.isEnabled, isFalse);
  });

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

  test(
      'explicit start resumes native disable despite cached Dart enabled state',
      () async {
    await client.startCollection(const TracerOptions());
    platform.nativeDisabled = true;
    expect(client.isEnabled, isTrue);
    final resumed = await client.startCollection();
    expect(resumed.isEnabled, isTrue);
    expect(client.isEnabled, isTrue);
    expect(platform.initializeCalls, 2);
    await client.startCollection();
    expect(platform.initializeCalls, 2);
  });

  test('stop during native state observation prevents a stale resume',
      () async {
    await client.startCollection(const TracerOptions());
    platform.nativeDisabled = true;
    platform.observing = Completer<void>();
    final resuming = client.startCollection();
    await Future<void>.delayed(Duration.zero);
    final stopped = client.stopAndClearCollection();
    platform.observing!.complete();
    expect((await resuming).reason, 'superseded');
    await stopped;
    expect(client.isEnabled, isFalse);
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
