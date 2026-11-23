import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:apptracer_flutter_desktop/src/macos_lifecycle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'close and clear require confirmation that native collection stopped',
    () async {
      final probe = NativeSdkProbe()
        ..onCall = (_) async => {'state': 'enabled'};
      probe.install();
      for (final method in ['closeNativeSdk', 'clearNativeSdk']) {
        await expectLater(MacOSLifecycle.invoke(method), throwsStateError);
      }
    },
  );

  test(
    'integration close failure remains visible across repeated stop and start',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var closeCalls = 0;
      final probe = NativeSdkProbe()
        ..onCall = (call) async {
          // The explicit pre-flush close succeeds. The integration called by
          // Sentry.close must still propagate its own failure.
          if (call.method == 'closeNativeSdk' && ++closeCalls == 2) {
            throw PlatformException(code: 'close_failed');
          }
          return null;
        };
      probe.install();
      final adapter = SentryDesktopTracer();
      const options = TracerOptions(
        dsn: 'https://public@tracer.invalid/42',
        release: '1',
      );
      expect((await adapter.startCollection(options)).isEnabled, true);
      await adapter.stopCollection();
      expect(adapter.isEnabled, false);
      expect(
        (await adapter.getCollectionState()).reason,
        'sentry_close_failed',
      );
      expect(
        (await adapter.stopAndClearCollection()).state,
        TracerCollectionState.error,
      );
      expect(
        (await adapter.startCollection(options)).state,
        TracerCollectionState.error,
      );
    },
  );
}
