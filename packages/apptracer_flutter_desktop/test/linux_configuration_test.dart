import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:apptracer_flutter_desktop/src/sdk_configuration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux registration and deferred bootstrap are inert', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SentryDesktopTracer.registerWith();
    final adapter = TracerPlatform.instance;
    expect(adapter, isA<SentryDesktopTracer>());
    await adapter.initialize(const TracerOptions(
        dsn: 'http://local@127.0.0.1/42',
        nativeInitialization: TracerNativeInitialization.deferred));
    expect(adapter.isEnabled, false);
    expect(Sentry.isEnabled, false);
    final result = await adapter.startCollection(
        const TracerOptions(dsn: 'http://public@remote.invalid/42'));
    expect(result.reason, 'invalid_sentry_dsn');
    expect(Sentry.isEnabled, false);
  });

  test('Linux does not install the SDK native auto-initializer', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final options = SentryFlutterOptions();
    configureDesktopSdk(
        options, const TracerOptions(dsn: 'https://public@tracer.invalid/42'));
    expect(options.enableAutoSessionTracking, false);
    expect(options.enableLogs, false);
    expect(options.enableMetrics, false);
    expect(options.tracesSampleRate, 0);
    expect(options.integrations.map((i) => i.runtimeType.toString()),
        isNot(contains('NativeSdkIntegration')));
  });
}
