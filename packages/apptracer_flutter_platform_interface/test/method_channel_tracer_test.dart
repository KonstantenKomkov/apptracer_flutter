import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_native_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a missing host returns unsupported over the real Pigeon channel',
      () async {
    final tracer = MethodChannelTracer(backendName: 'test');
    final stopped = await tracer.stopAndClearCollection();
    expect(stopped.state, TracerCollectionState.unsupported);
    expect(stopped.reason, 'native_operation_missing');
    expect((await tracer.setHeapDumpEnabled(false)).state,
        TracerDiagnosticState.unsupported);
  });

  test('an older host handles missing typed operations on the default channel',
      () async {
    const channel = MethodChannel(MethodChannelTracer.defaultChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'startCollection':
          return {'state': 'enabled'};
        case 'runHeapDump':
          return {'state': 'invoked', 'reason': 'legacy'};
        default:
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final tracer = MethodChannelTracer(backendName: 'legacy');
    const options = TracerOptions(appToken: 'token');
    expect((await tracer.startCollection(options)).isEnabled, isTrue);
    final diagnostic = await tracer.runHeapDump(tag: 'manual');
    expect(diagnostic.state, TracerDiagnosticState.invoked);
    expect(diagnostic.reason, 'legacy');
    await tracer.recordLog('log');
    await tracer.setCustomKey(key: 'k', value: 'v');
    await tracer.removeCustomKey('k');
    await tracer.setUserId(null);
    expect((await tracer.stopAndClearCollection()).reason,
        'invalid_native_result');
    expect(tracer.isEnabled, isFalse);
    expect(calls.map((call) => [call.method, call.arguments]), [
      ['startCollection', options.toMap()],
      [
        'runHeapDump',
        {'tag': 'manual'}
      ],
      [
        'recordLog',
        {'message': 'log'}
      ],
      [
        'setCustomKey',
        {'key': 'k', 'value': 'v'}
      ],
      [
        'removeCustomKey',
        {'key': 'k'}
      ],
      [
        'setUserId',
        {'userId': null}
      ],
      ['stopAndClearCollection', null],
    ]);
  });

  test('a typed host error does not replay an operation on the legacy host',
      () async {
    const channel = MethodChannel(MethodChannelTracer.defaultChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final replayed = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      replayed.add(call);
      return {'state': 'invoked'};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final tracer = MethodChannelTracer(
        backendName: 'typed',
        nativeApi: FakeNativeApi()..diagnosticError = platformError);
    await tracer.initialize(const TracerOptions());
    expect((await tracer.runDiskUsage()).reason, 'native_diagnostic_failed');
    expect(replayed, isEmpty);
  });

  test('an explicit channel is used even when a typed host is present',
      () async {
    const channel = MethodChannel('test/custom-tracer');
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binaryMessenger.setMockMethodCallHandler(channel, (call) async => true);
    addTearDown(() => binaryMessenger.setMockMethodCallHandler(channel, null));
    final native = FakeNativeApi();
    final tracer = MethodChannelTracer(
        channel: channel, backendName: 'test', nativeApi: native);
    await tracer.initialize(const TracerOptions());
    expect(tracer.isEnabled, isTrue);
    expect(native.calls, isEmpty);
  });

  late FakeNativeApi native;
  late MethodChannelTracer tracer;

  setUp(() {
    native = FakeNativeApi();
    tracer = MethodChannelTracer(backendName: 'test', nativeApi: native);
  });

  test('initialize forwards the typed options and enables', () async {
    await tracer.initialize(const TracerOptions(
      appToken: 'token',
      environment: 'prod',
      release: '1.0.0',
      maxBreadcrumbs: 25,
    ));

    expect(tracer.isEnabled, isTrue);
    final options = native.arguments['initialize']!.single! as NativeOptions;
    expect(options.appToken, 'token');
    expect(options.environment, 'prod');
    expect(options.release, '1.0.0');
    expect(options.maxBreadcrumbs, 25);
  });

  test('does not touch the platform when collection is disabled', () async {
    await tracer.initialize(const TracerOptions(isCollectionEnabled: false));
    expect(native.calls, isEmpty);
    expect(tracer.isEnabled, isFalse);
  });

  test('stays disabled when the native side declines to start', () async {
    native.initializeResult = false;
    await tracer.initialize(const TracerOptions(appToken: 'token'));
    expect(tracer.isEnabled, isFalse);
  });

  test('recordError forwards the whole typed event', () async {
    await tracer.initialize(const TracerOptions(appToken: 'token'));
    native.calls.clear();
    await tracer.recordError(TracerEvent(
      exceptionType: 'FormatException',
      message: 'bad input',
      stackTrace:
          DartStackTrace.parse('#0 inner (package:example/failing.dart:12:3)'),
      severity: TracerSeverity.warning,
      issueKey: 'ISSUE-1',
    ));

    final event = native.arguments['recordError']!.single! as NativeEvent;
    expect(event.exceptionType, 'FormatException');
    expect(event.severity, 'warning');
    expect(event.issueKey, 'ISSUE-1');
    expect(event.stackTrace.raw, contains('package:example/failing.dart'));
    expect(event.stackTrace.frames, hasLength(1));
  });

  test('does nothing before initialize', () async {
    await tracer.recordError(TracerEvent(
      exceptionType: 'StateError',
      message: 'boom',
      stackTrace: DartStackTrace.empty,
    ));
    await tracer.recordLog('hello');
    await tracer.setCustomKey(key: 'k', value: 'v');
    expect(native.calls, isEmpty);
  });

  test('a missing native implementation disables rather than throws', () async {
    native.initializeError = missingPlugin;
    await expectLater(
      tracer.initialize(const TracerOptions(appToken: 'token')),
      completes,
    );
    expect(tracer.isEnabled, isFalse);
  });

  test('a PlatformException from the native side does not propagate', () async {
    await tracer.initialize(const TracerOptions(appToken: 'token'));
    native.operationError = platformError;
    await expectLater(tracer.recordLog('hello'), completes);
  });

  test('forwards custom key and user id operations', () async {
    await tracer.initialize(const TracerOptions(appToken: 'token'));
    native.calls.clear();
    await tracer.setCustomKey(key: 'flavor', value: 'beta');
    await tracer.removeCustomKey('flavor');
    await tracer.setUserId('u-1');
    expect(
        native.calls, <String>['setCustomKey', 'removeCustomKey', 'setUserId']);
  });

  test('stopCollection disables the client', () async {
    await tracer.initialize(const TracerOptions(appToken: 'token'));
    await tracer.stopCollection();
    expect(tracer.isEnabled, isFalse);
    expect(native.calls.last, 'stopCollection');
  });
}
