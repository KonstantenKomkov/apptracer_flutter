import 'dart:io';

import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('release lookup failure prevents native startup', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final probe = NativeSdkProbe()..install();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (_) async => throw PlatformException(code: 'metadata_unavailable'),
        );
    final adapter = SentryDesktopTracer();
    final result = await adapter.startCollection(
      const TracerOptions(dsn: 'https://public@tracer.invalid/42'),
    );
    expect(result.reason, 'sentry_initialization_failed');
    expect(adapter.isEnabled, false);
    expect(probe.calls.map((c) => c.method), ['closeNativeSdk']);
  }, skip: !Platform.isMacOS);
}
