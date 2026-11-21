import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_native_api.dart';

void main() {
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
