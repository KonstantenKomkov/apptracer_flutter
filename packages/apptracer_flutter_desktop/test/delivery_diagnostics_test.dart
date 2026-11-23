import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sdk_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('delivery listener does not invent success confirmations', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final probe = NativeSdkProbe()..install();
    final adapter = SentryDesktopTracer();
    final diagnostics = <TracerDeliveryDiagnostic>[];
    const options = TracerOptions(
      dsn: 'https://public@tracer.invalid/42',
      nativeInitialization: TracerNativeInitialization.deferred,
    );

    await adapter.initialize(options);
    expect(adapter.isEnabled, isFalse);
    expect(probe.calls, isEmpty);
    final activeOptions = options.copyWith(deliveryListener: diagnostics.add);
    final started = await adapter.startCollection(activeOptions);
    addTearDown(adapter.stopCollection);
    expect(started.isEnabled, isTrue);

    await adapter.recordLog('breadcrumb');
    final messages = <String?>[];
    await Sentry.configureScope((scope) {
      messages.addAll(scope.breadcrumbs
          .where((crumb) => crumb.category == 'apptracer')
          .map((crumb) => crumb.message));
    });
    expect(messages, ['breadcrumb']);
    expect(diagnostics, isEmpty);

    // The Dart SDK logs and swallows a breadcrumb hook failure on every host.
    // ignore: invalid_use_of_internal_member
    Sentry.currentHub.options.beforeBreadcrumb =
        (_, __) => throw StateError('breadcrumb hook failed');
    await adapter.recordLog('failed breadcrumb');
    expect(diagnostics.single.state, TracerDeliveryState.failed);
    expect(diagnostics.single.backend, 'sentry-sdk');
    expect(diagnostics.single.operation, 'recordLog');
    expect(diagnostics.single.reason, 'operation_error');

    final pending = adapter.recordLog('previous session');
    adapter.configureDelivery(activeOptions, activateListener: false);
    adapter.configureDelivery(activeOptions);
    await pending;
    expect(diagnostics, hasLength(1));
    await adapter.recordLog('current session');
    expect(diagnostics, hasLength(2));
    expect(diagnostics.last.state, TracerDeliveryState.failed);
  });
}
