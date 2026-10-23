import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('invalid DSN, disabled and deferred bootstrap never start native SDK',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final probe = NativeSdkProbe()..install();
    final adapter = SentryDesktopTracer();
    for (final dsn in [
      null,
      '',
      'token',
      'https://host/1',
      'https://public:secret@host/1',
      'https://public@host/',
      'http://public@remote.invalid/42',
      'https://public@host/1?query=x'
    ]) {
      final result = await adapter.startCollection(TracerOptions(dsn: dsn));
      expect(result.isEnabled, false);
    }
    await adapter.initialize(const TracerOptions(
        dsn: 'https://public@tracer.invalid/42',
        nativeInitialization: TracerNativeInitialization.deferred));
    await adapter.startCollection(const TracerOptions(
        dsn: 'https://public@tracer.invalid/42', isCollectionEnabled: false));
    expect(probe.calls, isEmpty);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
        (await adapter.startCollection(
                const TracerOptions(dsn: 'https://public@tracer.invalid/42')))
            .state,
        TracerCollectionState.unsupported);
    expect(probe.calls, isEmpty);
  });
}
