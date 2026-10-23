import 'dart:async';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('stop during native startup cannot enable collection later', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final entered = Completer<void>();
    final release = Completer<void>();
    final probe = NativeSdkProbe()
      ..onCall = (call) async {
        if (call.method == 'initNativeSdk') {
          entered.complete();
          await release.future;
        }
        return null;
      };
    probe.install();
    final adapter = SentryDesktopTracer();
    final start = adapter.startCollection(const TracerOptions(
        dsn: 'https://public@tracer.invalid/42', release: '1'));
    await entered.future;
    final stop = adapter.stopCollection();
    release.complete();
    expect((await start).isEnabled, false);
    await stop;
    expect(adapter.isEnabled, false);
    expect(probe.events, isEmpty);
  });
}
