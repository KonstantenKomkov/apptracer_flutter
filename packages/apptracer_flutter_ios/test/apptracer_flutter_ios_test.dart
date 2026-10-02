import 'package:apptracer_flutter_ios/apptracer_flutter_ios.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MethodChannelTracer.defaultChannelName);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => true,
        'stopAndClearCollection' => <String, String>{
            'state': 'error',
            'reason': 'native_stop_and_cleanup_unverified',
          },
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('registerWith installs itself as the platform implementation', () {
    AppTracerIos.registerWith();

    expect(TracerPlatform.instance, isA<AppTracerIos>());
    expect(TracerPlatform.instance.backendName, 'ios-native');
  });

  test('talks over the shared channel', () async {
    final tracer = AppTracerIos();

    await tracer.initialize(const TracerOptions(appToken: 'required-on-ios'));
    await tracer.recordLog('breadcrumb');

    expect(tracer.isEnabled, isTrue);
    expect(calls.map((MethodCall c) => c.method),
        <String>['initialize', 'recordLog']);
  });

  test('revocation blocks new Dart events before the native channel', () async {
    final tracer = AppTracerIos();
    await tracer.initialize(const TracerOptions(appToken: 'required-on-ios'));

    final stopped = await tracer.stopAndClearCollection();
    expect(stopped.state, TracerCollectionState.error);
    expect(stopped.reason, 'native_stop_and_cleanup_unverified');
    expect(tracer.isEnabled, isFalse);

    final event = TracerEvent(
      exceptionType: 'StateError',
      message: 'after revocation',
      stackTrace: DartStackTrace.parse(''),
    );
    await tracer.recordError(event);
    await tracer.recordLog('after revocation');
    await tracer.setUserId('after-revocation');
    await tracer.setCustomKey(key: 'after', value: 'revocation');
    await tracer.removeCustomKey('before');

    expect(
      calls.map((MethodCall c) => c.method),
      <String>['initialize', 'stopAndClearCollection'],
    );
  });
}
