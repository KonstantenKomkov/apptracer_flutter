/// Web implementation of `apptracer_flutter`.
///
/// Tracer's own JavaScript SDK ships as an npm package (`@apptracer/sdk`),
/// which a Flutter web build has no way to bundle. This implementation speaks
/// the same HTTP ingest that SDK speaks — `POST /api/crash/uploadBatch`,
/// authenticated by the project's `appToken` — from pure Dart.
///
/// It used to send Sentry envelopes instead, on the belief that Tracer ingests
/// over the Sentry protocol everywhere. That belief did not survive contact: a
/// JS project is issued no DSN, and the vendor's SDK contains no Sentry
/// anywhere. The wire format used here was recovered from a captured request on
/// 2026-08-26 and is written down in `docs/web-protocol.md`.
///
/// The practical consequences are worth knowing:
///
/// * Errors thrown in JavaScript outside the Flutter application (a third-party
///   script, for instance) are not captured; only Dart errors are.
/// * Stack traces are `dart2js` frames. Tracer matches source maps by file
///   path rather than by Debug ID, so the paths in an uploaded source-map
///   archive must match the paths in the frames. See `docs/symbolication.md`.
/// * Breadcrumbs, custom keys and `userId` do travel, since 2026-08-27: the
///   vendor carries the log in a `logsFile` field whose format was read out of
///   its own SDK bundle. See `docs/web-protocol.md`.
library;

import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/window_browser_facts.dart';

export 'package:apptracer_flutter_http/apptracer_flutter_http.dart';
export 'src/window_browser_facts.dart';

/// The web [TracerPlatform] implementation.
class AppTracerWeb extends TracerHttpTracer {
  /// Creates the web implementation.
  AppTracerWeb()
      : super(
          facts: WindowBrowserFacts(),
          sdkVersion: packageVersion,
          backendName: 'web-tracer-http',
        );

  /// Version reported to Tracer as `tracerSdkVersion`.
  ///
  /// Ours, not the vendor's: what reaches their ingest comes from this package,
  /// and saying otherwise would make a support conversation confusing.
  static const String packageVersion = '0.1.0';

  /// Registers this class as the implementation for web.
  ///
  /// Called by the Flutter web plugin registrant; there is no need to call it
  /// from application code.
  static void registerWith(Registrar registrar) {
    TracerPlatform.instance = AppTracerWeb();
  }
}
