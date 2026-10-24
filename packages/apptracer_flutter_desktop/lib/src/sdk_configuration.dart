// The internal integration types are intentionally tied to sentry_flutter 9.30.1.
// A version update must re-audit the allowlist and native failure propagation.
// ignore_for_file: implementation_imports, experimental_member_use

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_flutter/src/integrations/native_load_debug_images_integration.dart';
import 'package:sentry_flutter/src/integrations/native_sdk_integration.dart';
import 'package:sentry_flutter/src/integrations/widgets_flutter_binding_integration.dart';

import 'macos_lifecycle.dart';

/// Configures the pinned SDK without installing a second Dart error owner.
void configureDesktopSdk(SentryFlutterOptions sdk, TracerOptions tracer) {
  sdk
    ..dsn = tracer.dsn!.trim()
    ..release = tracer.release
    ..environment = tracer.resolvedEnvironment
    ..dist = tracer.dist
    ..debug = false
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
    ..enableLogs = false
    ..enableMetrics = false
    ..enableDeduplication = false
    ..tracesSampleRate = 0
    ..profilesSampleRate = 0
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
        integration is! NativeSdkIntegration &&
        integration is! LoadNativeDebugImagesIntegration) {
      sdk.removeIntegration(integration);
    }
    if ((defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows) &&
        integration is NativeSdkIntegration) {
      sdk.removeIntegration(integration);
    }
  }
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    sdk.addIntegration(MacOSLifecycleIntegration(tracer));
  }
}

/// Records swallowed SDK/native failures without printing DSNs or payloads.
///
/// The SDK's default diagnostic logger is gated by `debug`; this observer is
/// deliberately independent of that gate. It sends no diagnostic telemetry.
class ObservedSdkOptions extends SentryFlutterOptions {
  /// Number of errors recorded at the SDK boundary.
  int failures = 0;

  @override
  SdkLogCallback get log => (
        SentryLevel level,
        String message, {
        String? logger,
        Object? exception,
        StackTrace? stackTrace,
      }) {
        if (level.ordinal >= SentryLevel.error.ordinal) failures++;
      };
}
