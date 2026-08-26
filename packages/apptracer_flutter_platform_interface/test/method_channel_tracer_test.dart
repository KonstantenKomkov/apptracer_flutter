import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MethodChannelTracer.defaultChannelName);
  final calls = <MethodCall>[];
  late MethodChannelTracer tracer;

  void mockHandler(Future<Object?>? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    tracer = MethodChannelTracer(backendName: 'test');
    mockHandler((MethodCall call) async => call.method == 'initialize');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initialize forwards the serialized options and enables', () async {
    await tracer.initialize(
      const TracerOptions(
        appToken: 'token',
        environment: 'prod',
        release: '1.0.0',
        maxBreadcrumbs: 25,
      ),
    );

    expect(tracer.isEnabled, isTrue);
    expect(calls.single.method, 'initialize');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['appToken'], 'token');
    expect(args['environment'], 'prod');
    expect(args['release'], '1.0.0');
    expect(args['maxBreadcrumbs'], 25);
  });

  test('does not touch the platform when collection is disabled', () async {
    await tracer.initialize(const TracerOptions(isCollectionEnabled: false));

    expect(calls, isEmpty);
    expect(tracer.isEnabled, isFalse);
  });

  test('stays disabled when the native side declines to start', () async {
    mockHandler((_) async => false);

    await tracer.initialize(const TracerOptions(appToken: 'token'));

    expect(tracer.isEnabled, isFalse);
  });

  test('recordError forwards the whole event', () async {
    await tracer.initialize(const TracerOptions(appToken: 'token'));
    calls.clear();

    await tracer.recordError(
      TracerEvent(
        exceptionType: 'FormatException',
        message: 'bad input',
        stackTrace: DartStackTrace.parse(
          '#0      inner (package:example/failing.dart:12:3)',
        ),
        severity: TracerSeverity.warning,
        issueKey: 'ISSUE-1',
      ),
    );

    expect(calls.single.method, 'recordError');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['exceptionType'], 'FormatException');
    expect(args['severity'], 'warning');
    expect(args['issueKey'], 'ISSUE-1');
    final stack = args['stackTrace']! as Map<Object?, Object?>;
    expect(stack['raw'], contains('package:example/failing.dart'));
    expect((stack['frames']! as List<Object?>), hasLength(1));
  });

  test('does nothing before initialize', () async {
    await tracer.recordError(
      TracerEvent(
        exceptionType: 'StateError',
        message: 'boom',
        stackTrace: DartStackTrace.empty,
      ),
    );
    await tracer.recordLog('hello');
    await tracer.setCustomKey(key: 'k', value: 'v');

    expect(calls, isEmpty);
  });

  test('a missing native implementation disables rather than throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    await expectLater(
      tracer.initialize(const TracerOptions(appToken: 'token')),
      completes,
    );
    expect(tracer.isEnabled, isFalse);
  });

  test('a PlatformException from the native side does not propagate', () async {
    await tracer.initialize(const TracerOptions(appToken: 'token'));
    mockHandler((_) async => throw PlatformException(code: 'boom'));

    await expectLater(tracer.recordLog('hello'), completes);
  });

  test('forwards custom key and user id operations', () async {
    await tracer.initialize(const TracerOptions(appToken: 'token'));
    calls.clear();

    await tracer.setCustomKey(key: 'flavor', value: 'beta');
    await tracer.removeCustomKey('flavor');
    await tracer.setUserId('u-1');

    expect(calls.map((MethodCall c) => c.method),
        <String>['setCustomKey', 'removeCustomKey', 'setUserId']);
  });

  test('stopCollection disables the client', () async {
    await tracer.initialize(const TracerOptions(appToken: 'token'));
    await tracer.stopCollection();

    expect(tracer.isEnabled, isFalse);
    expect(calls.last.method, 'stopCollection');
  });
}
