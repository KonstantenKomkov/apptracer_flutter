import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native purge failure is sticky and never reports disabled', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final probe = NativeSdkProbe()
      ..onCall = (call) async => call.method == 'clearNativeSdk'
          ? {'state': 'error', 'reason': 'native_cleanup_failed'}
          : null;
    probe.install();
    final adapter = SentryDesktopTracer();
    const options = TracerOptions(dsn: 'https://public@tracer.invalid/42');
    expect((await adapter.startCollection(options)).isEnabled, true);
    final result = await adapter.stopAndClearCollection();
    expect(result.state, TracerCollectionState.error);
    expect(result.reason, 'native_cleanup_failed');
    expect(adapter.isEnabled, false);
    expect((await adapter.stopAndClearCollection()).state,
        TracerCollectionState.error);
    expect((await adapter.startCollection(options)).state,
        TracerCollectionState.error);
    expect(probe.calls.where((c) => c.method == 'initNativeSdk'), hasLength(1));
    expect(
        probe.calls.where((c) => c.method == 'clearNativeSdk'), hasLength(1));
  });
}
