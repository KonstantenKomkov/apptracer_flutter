import 'dart:async';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_native_api.dart';

void main() {
  late FakeNativeApi native;
  late MethodChannelTracer platform;
  setUp(() {
    native = FakeNativeApi();
    platform = MethodChannelTracer(backendName: 'test', nativeApi: native);
  });

  test('pause and resume use public channel methods', () async {
    await platform.startCollection(const TracerOptions());
    final pause = platform.pauseCollection();
    expect(platform.isEnabled, isFalse);
    await pause;
    expect((await platform.resumeCollection()).isEnabled, isTrue);
    expect(platform.isEnabled, isTrue);
    expect(native.calls,
        ['startCollection', 'pauseCollection', 'resumeCollection']);
  });

  test('late resume answer cannot enable after clear', () async {
    native.resumeCompleter = Completer<NativeCollectionResult>();
    final resume = platform.resumeCollection();
    await Future<void>.delayed(Duration.zero);
    await platform.stopAndClearCollection();
    native.resumeCompleter!.complete(NativeCollectionResult(state: 'enabled'));
    expect((await resume).reason, 'superseded');
    expect(platform.isEnabled, isFalse);
  });

  test(
      'optional commands preserve arguments and distinguish invocation from delivery',
      () async {
    expect(
        (await platform.runDiskUsage()).state, TracerDiagnosticState.disabled);
    expect(native.calls, isEmpty);
    await platform.startCollection(const TracerOptions());
    expect((await platform.runHeapDump(tag: 'manual')).state,
        TracerDiagnosticState.invoked);
    expect(native.arguments['runHeapDump'], ['manual']);
    await platform.runDiskUsage();
    expect(native.calls.last, 'runDiskUsage');
    await platform.setHeapDumpEnabled(true);
    expect(native.arguments['setHeapDumpEnabled'], [true]);
  });

  test('missing optional commands and malformed replies fail explicitly',
      () async {
    native.diagnosticHandler = (_) => NativeDiagnosticResult(state: 'enabled');
    await platform.startCollection(const TracerOptions());
    expect((await platform.runDiskUsage()).reason, 'invalid_native_result');
    native.diagnosticError = missingPlugin;
    expect((await platform.runDiskUsage()).state,
        TracerDiagnosticState.unsupported);
  });

  test('native state and reason survive the channel', () async {
    native.collectionHandler = (_) => NativeCollectionResult(
        state: 'restartRequired', reason: 'one_way_disable');
    final result = await platform.startCollection(const TracerOptions());
    expect(result.state, TracerCollectionState.restartRequired);
    expect(result.reason, 'one_way_disable');
    expect(platform.isEnabled, isFalse);
  });

  test('missing operation is unsupported without guessing purge success',
      () async {
    native.collectionError = missingPlugin;
    final result = await platform.stopAndClearCollection();
    expect(result.state, TracerCollectionState.unsupported);
  });

  test('native cleanup errors are visible and revoke events immediately',
      () async {
    native.collectionError = platformError;
    await platform.startCollection(const TracerOptions());
    final pending = platform.stopAndClearCollection();
    expect(platform.isEnabled, isFalse);
    expect((await pending).state, TracerCollectionState.error);
  });

  test('late initialize answer cannot enable after stop', () async {
    native.initializeCompleter = Completer<bool>();
    final start = platform.initialize(const TracerOptions());
    await Future<void>.delayed(Duration.zero);
    await platform.stopCollection();
    native.initializeCompleter!.complete(true);
    await start;
    expect(platform.isEnabled, isFalse);
  });

  test('querying native enabled state does not grant Dart permission',
      () async {
    expect((await platform.getCollectionState()).isEnabled, isTrue);
    expect(platform.isEnabled, isFalse);
  });
}
