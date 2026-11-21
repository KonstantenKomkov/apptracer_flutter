import 'package:apptracer_flutter_android/apptracer_flutter_android.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../apptracer_flutter_platform_interface/test/fake_native_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerWith installs itself as the platform implementation', () {
    AppTracerAndroid.registerWith();
    expect(TracerPlatform.instance, isA<AppTracerAndroid>());
    expect(TracerPlatform.instance.backendName, 'android-native');
  });

  test('talks over the generated shared contract', () async {
    final native = FakeNativeApi();
    final tracer = AppTracerAndroid(nativeApi: native);
    await tracer
        .initialize(const TracerOptions(appToken: 'ignored-on-android'));
    await tracer.recordLog('breadcrumb');

    expect(tracer.isEnabled, isTrue);
    expect(native.calls, <String>['initialize', 'recordLog']);
  });
}
