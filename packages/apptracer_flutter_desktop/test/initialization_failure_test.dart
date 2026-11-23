import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native startup failure is not hidden and appRunner runs once',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final probe = NativeSdkProbe()
      ..onCall = (call) async {
        if (call.method == 'initNativeSdk') {
          throw PlatformException(
              code: 'native_unavailable', message: 'private DSN');
        }
        return null;
      };
    probe.install();
    final adapter = SentryDesktopTracer();
    final previousPlatform = TracerPlatform.instance;
    addTearDown(() => TracerPlatform.instance = previousPlatform);
    TracerPlatform.instance = adapter;
    var runs = 0;
    final original = FlutterError.onError;
    await Tracer.initialize(
      options: const TracerOptions(
          dsn: 'https://public@tracer.invalid/42',
          release: '1',
          captureZoneErrors: false),
      appRunner: () {
        runs++;
      },
    );
    expect(runs, 1);
    expect(Tracer.isEnabled, false);
    expect(FlutterError.onError, same(original));
    expect((await adapter.getCollectionState()).reason,
        'sentry_initialization_failed');
    expect(probe.events, isEmpty);

    // A fresh object must not bypass the process owner after a failed start.
    final other = SentryDesktopTracer();
    final restarted = await other.startCollection(
      const TracerOptions(dsn: 'https://public@tracer.invalid/42'),
    );
    expect(restarted.state, TracerCollectionState.error);
    expect(restarted.reason, 'sentry_already_owned');
    expect(probe.calls.where((call) => call.method == 'initNativeSdk'),
        hasLength(1));
  });
}
