// The internal integration types are intentionally tied to sentry_flutter 10.6.0.
// A version update must re-audit the allowlist and native failure propagation.
// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart'
    show TracerOptions;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_flutter/src/bindings/widgets_flutter_binding_integration.dart';
import 'package:sentry_flutter/src/debug_images/native_load_debug_images_integration.dart';

/// Configures the pinned SDK without installing a second Dart error owner.
void configureDesktopSdk(SentryFlutterOptions sdk, TracerOptions tracer) {
  sdk
    ..release = tracer.release
    ..environment = tracer.resolvedEnvironment
    ..dist = tracer.dist
    ..debug = false
    ..autoInitializeNativeSdk = false
    ..sendDefaultPii = false
    ..attachStacktrace = false
    ..attachThreads = false
    ..enableAutoSessionTracking = false
    ..enableAutoNativeBreadcrumbs = false
    ..enableAutoPerformanceTracing = false
    ..enableNativeTraceSync = false
    ..enableUserInteractionTracing = false
    ..enableTimeToFullDisplayTracing = false
    ..enableFramesTracking = false
    ..enableAppHangTracking = false
    ..enableWatchdogTerminationTracking = false
    ..enableDeduplication = false
    ..tracesSampleRate = 0
    ..maxBreadcrumbs = tracer.maxBreadcrumbs
    ..attachScreenshot = false
    ..attachViewHierarchy = false;
  sdk.replay
    ..sessionSampleRate = 0
    ..onErrorSampleRate = 0;
  sdk.spotlight = Spotlight(enabled: false);
  for (final integration in sdk.integrations.toList()) {
    if (integration is! WidgetsFlutterBindingIntegration &&
        integration is! LoadReleaseIntegration &&
        integration is! LoadNativeDebugImagesIntegration) {
      sdk.removeIntegration(integration);
    }
  }
}

/// Observes failures at the SDK boundaries owned by this adapter. Sentry 10's
/// diagnostic logger is compiled out in release.
class ObservedSdkOptions extends SentryFlutterOptions {
  final _operationKey = Object();
  final _propagateKey = Object();

  _SdkOperation? get _operation =>
      Zone.current[_operationKey] as _SdkOperation?;

  /// Sentry 10.6.0 uses this switch to propagate otherwise swallowed
  /// exceptions. Only an awaited scope update or transport send opts in.
  /// Event enrichment and unrelated SDK calls retain their normal fallbacks.
  @override
  bool get automatedTestMode =>
      Zone.current[_propagateKey] == true && _operation?.active == true;

  /// Records failures in this operation's async chain, without retaining
  /// the exception, payload or stack trace.
  Future<bool> loggedErrorDuring(Future<void> Function() action) async {
    final operation = _SdkOperation();
    try {
      await runZoned(action, zoneValues: {_operationKey: operation});
    } catch (_) {
      if (!operation.failed) rethrow;
    } finally {
      operation.active = false;
    }
    return operation.failed;
  }

  /// Lets the SDK propagate failures from the scope or transport boundary.
  Future<T> observeSdkCall<T>(Future<T> Function() action) {
    final operation = _operation;
    if (operation == null || !operation.active) return action();
    return _observeCallback(
      () => runZoned(action, zoneValues: {_propagateKey: true}),
    );
  }

  /// Observe the selected platform transport after the adapter configures it.
  void observeTransport() {
    transport = _ObservedTransport(this, transport);
  }

  // Observe callbacks before Sentry catches their exceptions. A normal null
  // result is an intentional drop and does not indicate a failed operation.
  @override
  set beforeSend(BeforeSendCallback? callback) {
    super.beforeSend = callback == null
        ? null
        : (event, hint) => _observeCallback(() => callback(event, hint));
  }

  @override
  List<EventProcessor> get eventProcessors {
    final processors = super.eventProcessors;
    if (_operation?.active != true) return processors;
    return List.unmodifiable(
      processors.map((processor) => _ObservedProcessor(this, processor)),
    );
  }

  Future<T> _observeCallback<T>(FutureOr<T> Function() callback) async {
    try {
      return await callback();
    } catch (_) {
      _operation?.failed = true;
      rethrow;
    }
  }
}

class _SdkOperation {
  bool active = true;
  bool failed = false;
}

class _ObservedTransport implements Transport {
  _ObservedTransport(this.options, this.delegate);
  final ObservedSdkOptions options;
  final Transport delegate;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) =>
      options.observeSdkCall(() => delegate.send(envelope));
}

class _ObservedProcessor implements EventProcessor {
  _ObservedProcessor(this.options, this.delegate);
  final ObservedSdkOptions options;
  final EventProcessor delegate;

  @override
  Future<SentryEvent?> apply(SentryEvent event, Hint hint) =>
      options._observeCallback(() => delegate.apply(event, hint));
}
