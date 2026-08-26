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
      return call.method == 'initialize' ? true : null;
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
}
