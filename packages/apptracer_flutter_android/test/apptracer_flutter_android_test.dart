import 'package:apptracer_flutter_android/apptracer_flutter_android.dart';
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
      return call.method == 'initialize' ? true : null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('registerWith installs itself as the platform implementation', () {
    AppTracerAndroid.registerWith();

    expect(TracerPlatform.instance, isA<AppTracerAndroid>());
    expect(TracerPlatform.instance.backendName, 'android-native');
  });

  test('talks over the shared channel', () async {
    final tracer = AppTracerAndroid();

    await tracer
        .initialize(const TracerOptions(appToken: 'ignored-on-android'));
    await tracer.recordLog('breadcrumb');

    expect(tracer.isEnabled, isTrue);
    expect(calls.map((MethodCall c) => c.method),
        <String>['initialize', 'recordLog']);
  });
}
