import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native close failure remains visible across repeated stop and start',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var failClose = false;
    final probe = NativeSdkProbe()
      ..onCall = (call) async {
        if (failClose && call.method == 'closeNativeSdk') {
          throw PlatformException(code: 'close_failed');
        }
        return null;
      };
    probe.install();
    final adapter = SentryDesktopTracer();
    const options =
        TracerOptions(dsn: 'https://public@tracer.invalid/42', release: '1');
    expect((await adapter.startCollection(options)).isEnabled, true);
    failClose = true;
    await adapter.stopCollection();
    expect(adapter.isEnabled, false);
    expect((await adapter.getCollectionState()).reason, 'sentry_close_failed');
    expect((await adapter.stopAndClearCollection()).state,
        TracerCollectionState.error);
    expect((await adapter.startCollection(options)).state,
        TracerCollectionState.error);
  });
}
