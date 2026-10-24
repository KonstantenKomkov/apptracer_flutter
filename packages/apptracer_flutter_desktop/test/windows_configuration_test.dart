// ignore_for_file: experimental_member_use

import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:apptracer_flutter_desktop/src/sdk_configuration.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows registration and deferred bootstrap do not load native SDK',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final previous = TracerPlatform.instance;
    addTearDown(() => TracerPlatform.instance = previous);
    SentryDesktopTracer.registerWith();
    final adapter = TracerPlatform.instance;
    expect(adapter, isA<SentryDesktopTracer>());
    await adapter.initialize(const TracerOptions(
      dsn: 'https://public@tracer.invalid/42',
      nativeInitialization: TracerNativeInitialization.deferred,
    ));
    expect(adapter.isEnabled, false);
    expect(Sentry.isEnabled, false);
    expect((await adapter.getCollectionState()).state,
        TracerCollectionState.disabled);
    // Missing credentials must not attempt to load sentry.dll on any host.
    expect((await adapter.startCollection(const TracerOptions())).state,
        TracerCollectionState.disabled);
    expect(Sentry.isEnabled, false);
  });

  test('Windows SDK configuration disables automatic telemetry', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final options = SentryFlutterOptions();
    configureDesktopSdk(
        options, const TracerOptions(dsn: 'https://public@tracer.invalid/42'));
    expect(options.enableAutoSessionTracking, false);
    expect(options.enableLogs, false);
    expect(options.enableMetrics, false);
    expect(options.tracesSampleRate, 0);
    expect(options.profilesSampleRate, 0);
    expect(options.integrations.whereType<OnErrorIntegration>(), isEmpty);
    expect(options.integrations.map((item) => item.runtimeType.toString()),
        isNot(contains('FlutterErrorIntegration')));
    expect(options.integrations.map((item) => item.runtimeType.toString()),
        isNot(contains('NativeSdkIntegration')));
  });
}
