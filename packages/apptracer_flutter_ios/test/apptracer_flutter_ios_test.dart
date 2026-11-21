import 'package:apptracer_flutter_ios/apptracer_flutter_ios.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../apptracer_flutter_platform_interface/test/fake_native_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerWith installs itself as the platform implementation', () {
    AppTracerIos.registerWith();
    expect(TracerPlatform.instance, isA<AppTracerIos>());
    expect(TracerPlatform.instance.backendName, 'ios-native');
  });

  test('talks over the generated shared contract', () async {
    final native = FakeNativeApi();
    final tracer = AppTracerIos(nativeApi: native);
    await tracer.initialize(const TracerOptions(appToken: 'required-on-ios'));
    await tracer.recordLog('breadcrumb');

    expect(tracer.isEnabled, isTrue);
    expect(native.calls, <String>['initialize', 'recordLog']);
  });

  test('revocation blocks new Dart events before the native channel', () async {
    final native = FakeNativeApi();
    native.collectionHandler = (_) => NativeCollectionResult(
        state: 'error', reason: 'native_stop_and_cleanup_unverified');
    final tracer = AppTracerIos(nativeApi: native);
    await tracer.initialize(const TracerOptions(appToken: 'required-on-ios'));

    final stopped = await tracer.stopAndClearCollection();
    expect(stopped.state, TracerCollectionState.error);
    expect(stopped.reason, 'native_stop_and_cleanup_unverified');
    expect(tracer.isEnabled, isFalse);

    await tracer.recordError(TracerEvent(
      exceptionType: 'StateError',
      message: 'after revocation',
      stackTrace: DartStackTrace.parse(''),
    ));
    await tracer.recordLog('after revocation');
    await tracer.setUserId('after-revocation');
    await tracer.setCustomKey(key: 'after', value: 'revocation');
    await tracer.removeCustomKey('before');

    expect(native.calls, <String>['initialize', 'stopAndClearCollection']);
  });
}
