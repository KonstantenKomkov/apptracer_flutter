/// Unofficial Flutter integration with Tracer (https://apptracer.ru), the
/// error-monitoring service by OK.TECH / VK.
///
/// This package is **not** affiliated with, endorsed by, or supported by VK or
/// OK.TECH. It wraps the vendor's public SDKs; it does not redistribute them.
///
/// It exists because the native Tracer SDKs cannot see Dart errors. The Android
/// SDK installs a `Thread.UncaughtExceptionHandler`, a native signal handler
/// and an ANR watchdog; an unhandled Dart exception never reaches any of them,
/// because it does not terminate the process and never enters the JVM. Flutter
/// intercepts it inside Dart instead. This package hooks the three Dart-side
/// entry points — `FlutterError.onError`,
/// `PlatformDispatcher.instance.onError` and the errors of a guarded zone —
/// and forwards what it finds to the native SDK.
///
/// ```dart
/// void main() {
///   Tracer.initialize(
///     options: const TracerOptions(
///       appToken: String.fromEnvironment('TRACER_APP_TOKEN'),
///       environment: 'prod',
///       release: '1.0.0',
///     ),
///     appRunner: () => runApp(const MyApp()),
///   );
/// }
/// ```
library;

import 'dart:async';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/widgets.dart';

import 'src/tracer_client.dart';

export 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart'
    show
        BeforeBreadcrumbCallback,
        BeforeSendCallback,
        DartStackFrame,
        DartStackTrace,
        SyntheticIssueKey,
        TracerBreadcrumb,
        TracerEvent,
        TracerOptions,
        TracerPlatform,
        TracerSeverity,
        UnsupportedTracerPlatform;

export 'src/breadcrumb_buffer.dart';
export 'src/deduplicator.dart';
export 'src/error_handler_chain.dart';
export 'src/error_normalizer.dart';
export 'src/tracer_client.dart';

/// The entry point of the integration.
///
/// Every method is safe to call before [initialize] and after
/// [stopCollection]; calls simply do nothing while collection is off.
abstract final class Tracer {
  static TracerClient _client = TracerClient();

  /// The client backing the facade.
  ///
  /// Exposed so tests can substitute a client wired to a fake platform.
  @visibleForTesting
  static TracerClient get client => _client;

  @visibleForTesting
  static set client(TracerClient value) => _client = value;

  /// Whether collection is currently running.
  static bool get isEnabled => _client.isEnabled;

  /// The breadcrumbs buffered so far, oldest first.
  static List<TracerBreadcrumb> get breadcrumbs => _client.breadcrumbs;

  /// Starts the integration and then runs the application.
  ///
  /// [appRunner] — normally `() => runApp(const MyApp())` — is invoked
  /// **exactly once, in every scenario**: when the SDK starts normally, when
  /// collection is switched off through
  /// [TracerOptions.isCollectionEnabled], when the platform SDK throws while
  /// starting, and when no implementation exists for the current platform. An
  /// error reporter that can stop an application from starting is worse than
  /// no error reporter.
  ///
  /// When [TracerOptions.captureZoneErrors] is set — the default — the
  /// application runs inside a guarded zone so that uncaught asynchronous
  /// errors are captured. `WidgetsFlutterBinding.ensureInitialized()` is called
  /// inside that same zone, which is what Flutter expects.
  ///
  /// The returned future completes once [appRunner] has returned. If
  /// [appRunner] itself throws, the error is reported to Tracer and the future
  /// completes with it.
  static Future<void> initialize({
    required TracerOptions options,
    required FutureOr<void> Function() appRunner,
  }) {
    var appRunnerCalled = false;

    Future<void> bootstrap() async {
      try {
        WidgetsFlutterBinding.ensureInitialized();
        await _client.start(options);
      } catch (error, stackTrace) {
        // Starting the reporter must never be the reason an app fails to boot.
        if (options.debug) {
          debugPrint('apptracer_flutter: initialization failed: $error');
          debugPrint('$stackTrace');
        }
      }
      if (appRunnerCalled) {
        return;
      }
      appRunnerCalled = true;
      await appRunner();
    }

    if (!options.captureZoneErrors) {
      // Without a guarded zone there is nothing to catch an appRunner failure,
      // so report it here rather than letting the one error that matters most —
      // the app failing to start — be the only one that never arrives.
      return bootstrap().catchError((Object error, StackTrace stackTrace) {
        _client.recordUnhandledError(error, stackTrace);
        throw error;
      });
    }

    final completer = Completer<void>();
    runZonedGuarded<void>(
      () {
        bootstrap().then(
          (_) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _client.handleZoneError(error, stackTrace);
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        );
      },
      (Object error, StackTrace stackTrace) {
        _client.handleZoneError(error, stackTrace);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  /// Stops collection, uninstalls the error handlers and restores whichever
  /// handlers were in place beforehand.
  ///
  /// After this call a fresh [initialize] starts from a clean slate rather than
  /// stacking a second set of handlers on top of the first.
  static Future<void> stopCollection() => _client.stop();

  /// Reports a caught error.
  ///
  /// [fatal] marks the error as terminating. Note that on Android and iOS a
  /// fatal report counts against the crash-free metric, so reserve it for
  /// errors that genuinely ended the session.
  ///
  /// [issueKey] overrides Tracer's stack-trace-based grouping, which is useful
  /// when the throw site says more about the problem than the stack does.
  static Future<void> recordError(
    Object? error,
    StackTrace? stackTrace, {
    TracerSeverity severity = TracerSeverity.error,
    bool fatal = false,
    String? issueKey,
    Map<String, String> customKeys = const <String, String>{},
  }) {
    return _client.recordError(
      error,
      stackTrace,
      severity: severity,
      fatal: fatal,
      issueKey: issueKey,
      customKeys: customKeys,
    );
  }

  /// Reports a `FlutterErrorDetails` by hand.
  ///
  /// Only needed when [TracerOptions.captureFlutterErrors] is off and the
  /// application forwards framework errors itself.
  static void recordFlutterError(FlutterErrorDetails details) =>
      _client.recordFlutterError(details);

  /// Adds a breadcrumb to the trail attached to later events.
  static void addBreadcrumb(TracerBreadcrumb breadcrumb) =>
      _client.addBreadcrumb(breadcrumb);

  /// Convenience wrapper around [addBreadcrumb].
  static void log(
    String message, {
    String? category,
    TracerSeverity level = TracerSeverity.info,
    Map<String, String> data = const <String, String>{},
  }) {
    _client.addBreadcrumb(
      TracerBreadcrumb(
        message: message,
        category: category,
        level: level,
        data: data,
      ),
    );
  }

  /// Writes [message] straight into the platform log buffer, bypassing the
  /// breadcrumb pipeline and [TracerOptions.beforeBreadcrumb].
  static Future<void> recordLog(String message) => _client.recordLog(message);

  /// Sets a custom key attached to every subsequent event.
  ///
  /// Tracer truncates keys at 31 characters and values at 128, and keeps at
  /// most 30 of them.
  static Future<void> setCustomKey({
    required String key,
    required String value,
  }) =>
      _client.setCustomKey(key: key, value: value);

  /// Removes a previously set custom key.
  static Future<void> removeCustomKey(String key) =>
      _client.removeCustomKey(key);

  /// Associates subsequent events with [userId], or clears it when `null`.
  ///
  /// A user identifier is personal data and nothing sets it automatically.
  /// Call this only where you have a lawful basis; see `docs/privacy.md`.
  static Future<void> setUserId(String? userId) => _client.setUserId(userId);
}
