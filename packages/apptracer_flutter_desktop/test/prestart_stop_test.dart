import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('explicit prestart stop revokes replay without starting the SDK',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final probe = NativeSdkProbe()
      ..onCall = (call) async => call.method == 'initNativeSdk'
          ? {'state': 'enabled'}
          : {'state': 'disabled'};
    probe.install();
    final adapter = SentryDesktopTracer();
    await adapter.initialize(const TracerOptions(
      dsn: 'https://public@tracer.invalid/42',
      nativeInitialization: TracerNativeInitialization.deferred,
    ));
    expect(probe.calls, isEmpty);
    await adapter.stopCollection();
    expect(probe.calls.map((c) => c.method), ['closeNativeSdk']);
    // A later start must not slip between close and purge of a prestart clear.
    final clear = adapter.stopAndClearCollection();
    final start = adapter.startCollection(const TracerOptions(
      dsn: 'https://public@tracer.invalid/42',
      preservePreviousReports: true,
    ));
    expect((await clear).state, TracerCollectionState.disabled);
    expect((await start).isEnabled, true);
    expect(adapter.isEnabled, true);
    expect(probe.calls.indexWhere((c) => c.method == 'clearNativeSdk'),
        lessThan(probe.calls.indexWhere((c) => c.method == 'initNativeSdk')));
    final init = probe.calls.singleWhere((c) => c.method == 'initNativeSdk');
    expect((init.arguments as Map)['preservePreviousReports'], true);
    final close = probe.calls.first.arguments as Map;
    expect((init.arguments as Map)['owner'], close['owner']);
    expect(close['owner'], isNotEmpty);
  });
}
