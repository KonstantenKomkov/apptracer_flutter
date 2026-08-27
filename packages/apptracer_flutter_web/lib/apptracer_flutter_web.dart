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

import 'dart:convert';
import 'dart:js_interop';

import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

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

  /// Fills in the application's version before starting.
  ///
  /// `flutter build web` writes `version.json` next to `index.html`, carrying
  /// the `version:` from `pubspec.yaml`. Reading it here is what keeps
  /// `release` and `dist` out of an application's `TracerOptions`: Android and
  /// iOS take the version from their bundle, and this is web's equivalent.
  ///
  /// A build served from a subdirectory, or one whose `version.json` was
  /// stripped, simply keeps whatever the options already said. A crash
  /// reporter that refuses to start because it could not read a version file
  /// would be worse than one reporting an unknown version.
  @override
  Future<void> initialize(TracerOptions options) async {
    if (options.release != null && options.dist != null) {
      return super.initialize(options);
    }

    final Map<String, Object?>? version = await _readVersionJson();
    if (version == null) {
      return super.initialize(options);
    }

    return super.initialize(options.copyWith(
      release: options.release ?? version['version'] as String?,
      dist: options.dist ?? version['build_number'] as String?,
    ));
  }

  Future<Map<String, Object?>?> _readVersionJson() async {
    try {
      final String base = web.window.document.baseURI;
      final web.Response response =
          await web.window.fetch('${base}version.json'.toJS).toDart;
      if (!response.ok) {
        return null;
      }
      final String body = (await response.text().toDart).toDart;
      return jsonDecode(body) as Map<String, Object?>;
    } on Object {
      // A missing or unreadable version.json is not a reason to report nothing.
      return null;
    }
  }

  /// Registers this class as the implementation for web.
  ///
  /// Called by the Flutter web plugin registrant; there is no need to call it
  /// from application code.
  static void registerWith(Registrar registrar) {
    TracerPlatform.instance = AppTracerWeb();
  }
}
