import 'dart:async';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_desktop/apptracer_flutter_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/native/native_scope_observer.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/native/sentry_native_channel.dart';

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

    // Match the mocked macOS lifecycle with a channel-backed scope observer.
    // Sentry otherwise chooses the Linux/Windows FFI binding from the host OS.
    // ignore: invalid_use_of_internal_member
    final sdk = Sentry.currentHub.options as SentryFlutterOptions;
    final nativeObserver = sdk.scopeObservers
        .indexWhere((observer) => observer is NativeScopeObserver);
    // ignore: invalid_use_of_internal_member
    sdk.scopeObservers[nativeObserver] =
        NativeScopeObserver(SentryNativeChannel(sdk), sdk);

    // Finish an earlier, unrelated SDK call while recordLog awaits native sync.
    final syncing = Completer<void>();
    final unrelated = Sentry.configureScope((_) async {
      await syncing.future;
      throw StateError('unrelated scope failure');
    });
    probe.onCall = (call) async {
      if (call.method == 'addBreadcrumb') {
        syncing.complete();
        await unrelated;
      }
      return null;
    };
    await adapter.recordLog('breadcrumb');
    probe.onCall = null;
    expect(syncing.isCompleted, isTrue);
    final messages = <String?>[];
    await Sentry.configureScope((scope) {
      messages.addAll(scope.breadcrumbs
          .where((crumb) => crumb.category == 'apptracer')
          .map((crumb) => crumb.message));
    });
    expect(messages, ['breadcrumb']);
    expect(diagnostics, isEmpty);

    // The Dart SDK logs and swallows a breadcrumb hook failure on every host.
    sdk.beforeBreadcrumb =
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

    sdk.beforeBreadcrumb = null;
    probe.onCall = (call) async {
      if (call.method == 'addBreadcrumb') {
        throw PlatformException(code: 'native_scope_failure');
      }
      return null;
    };
    await adapter.recordLog('current session');
    expect(diagnostics, hasLength(2));
    expect(diagnostics.last.state, TracerDeliveryState.failed);
    expect(diagnostics.last.operation, 'recordLog');
    expect(diagnostics.last.reason, 'operation_error');
  });
}
