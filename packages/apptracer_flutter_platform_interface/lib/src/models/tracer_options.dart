import 'package:flutter/foundation.dart';

import 'tracer_breadcrumb.dart';
import 'tracer_collection_result.dart';
import 'tracer_delivery_diagnostic.dart';
import 'tracer_event.dart';

/// Controls what happens when a Dart event or breadcrumb filter throws.
enum TracerFilterErrorPolicy {
  /// Deliver the original value, preserving the historical behavior.
  sendOriginal,

  /// Drop the value without calling the failed filter again or forwarding it.
  drop,
}

/// Inspects and optionally rewrites an event before it is delivered.
///
/// Return `null` to drop the event. The callback runs on the Dart isolate that
/// reported the error and must not block.
typedef BeforeSendCallback = TracerEvent? Function(TracerEvent event);

/// Inspects and optionally rewrites a breadcrumb before it is buffered.
///
/// Return `null` to drop the breadcrumb.
typedef BeforeBreadcrumbCallback = TracerBreadcrumb? Function(
  TracerBreadcrumb breadcrumb,
);

/// Configuration for the Tracer integration.
///
/// Every field that could carry personal data is off by default. See
/// `docs/privacy.md` for the full list of what is transmitted and when.
@immutable
class TracerOptions {
  /// Creates a set of options.
  const TracerOptions({
    this.appToken,
    this.iosAppToken,
    this.webAppToken,
    this.dsn,
    this.environment,
    this.release,
    this.dist,
    this.isCollectionEnabled = true,
    this.nativeInitialization = TracerNativeInitialization.automatic,
    this.preservePreviousReports = false,
    this.beforeSend,
    this.beforeBreadcrumb,
    this.filterErrorPolicy = TracerFilterErrorPolicy.sendOriginal,
    this.deliveryListener,
    this.maxBreadcrumbs = 100,
    this.captureFlutterErrors = true,
    this.capturePlatformDispatcherErrors = true,
    this.captureZoneErrors = true,
    this.reportUnhandledErrorsAsFatal = false,
    this.attachRawStackTraceAsLog = true,
    this.maxRawStackTraceLogBytes = 8192,
    this.maxStackFrames = 128,
    this.debug = false,
    this.apiUrl,
    this.initialCustomKeys = const <String, String>{},
  });

  /// The Tracer application token, found under *Настройки → Проект → API*.
  ///
  /// An iOS-only or Web-only app can use its project's token here. Use
  /// [iosAppToken] and [webAppToken] for separate projects in a shared build.
  ///
  /// Whichever of the three applies is resolved by [resolvedAppToken], which is
  /// what implementations read.
  ///
  /// **Android ignores this value.** The Android SDK reads its token from
  /// resources generated at build time by the `ru.ok.tracer` Gradle plugin,
  /// and there is no supported runtime override outside an `Application`
  /// subclass. See `docs/platform-matrix.md`.
  final String? appToken;

  /// The iOS project's token, used instead of [appToken] on iOS.
  final String? iosAppToken;

  /// The web (JS) project's token, used instead of [appToken] on web.
  final String? webAppToken;

  /// The token that applies to the platform this build is running on.
  ///
  /// Android is not among them on purpose: its SDK reads the token from a
  /// resource the Gradle plugin generates, and nothing passed from Dart can
  /// change that.
  String? get resolvedAppToken {
    if (kIsWeb) {
      return webAppToken ?? appToken;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return iosAppToken ?? appToken;
    }
    return appToken;
  }

  /// The Sentry DSN of the target desktop project in Tracer.
  ///
  /// Add the optional stable `apptracer_flutter_desktop` dependency. Flutter
  /// registers its adapter on desktop, and the adapter passes this DSN to the
  /// official Sentry SDK. Web uses [webAppToken] or [appToken].
  /// See the [supported configurations](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md#summary).
  final String? dsn;

  /// Deployment environment, for example `prod`, `test` or `dev`.
  ///
  /// Optional: [resolvedEnvironment] falls back to `prod` in a release build
  /// and `dev` otherwise. Android ignores it either way — there the SDK takes
  /// the environment from the Gradle plugin.
  final String? environment;

  /// Application version reported to Tracer.
  ///
  /// Optional, and usually left alone. Android and iOS take the version from
  /// the application bundle themselves; web fills it in from the `version.json`
  /// that `flutter build web` writes, which carries the version out of
  /// `pubspec.yaml`. Set this only to report something other than that.
  ///
  /// Tracer strips everything up to and including the last `@` when the value
  /// looks like `<application>@<version>`, so `my_app@1.2.3` is recorded as
  /// `1.2.3`. Plain semantic versions are recommended.
  final String? release;

  /// Build distribution identifier, for example a CI build number.
  ///
  /// Also filled in from `version.json` on web, where it becomes the numeric
  /// `versionCode` the ingest expects.
  final String? dist;

  /// Whether collection is allowed at all.
  ///
  /// When false, Dart collection stays off. Android automatic providers run
  /// before Dart; use deferred mode and its manifest setup for consent gating.
  final bool isCollectionEnabled;

  /// In deferred mode bootstrap runs the app without starting the native SDK.
  /// Explicitly call Tracer.startCollection after the application's decision.
  /// Android also requires removal of both startup providers in the manifest.
  final TracerNativeInitialization nativeInitialization;

  /// Retains reports from an earlier launch in native deferred mode.
  /// Only enable after verifying that the earlier reporting session belongs to
  /// the same authorized account. A recorded purge obligation overrides this.
  /// Defaults to discarding previous reports before native senders start.
  final bool preservePreviousReports;

  /// Hook invoked for every event just before delivery.
  final BeforeSendCallback? beforeSend;

  /// Hook invoked for every breadcrumb just before it is buffered.
  final BeforeBreadcrumbCallback? beforeBreadcrumb;

  /// Whether a throwing [beforeSend] or [beforeBreadcrumb] keeps or drops the
  /// original Dart value. Defaults to [TracerFilterErrorPolicy.sendOriginal]
  /// for compatibility; reconsider this default before API 2.0.
  ///
  /// This policy cannot filter native crashes or data already captured by a
  /// native SDK. Applications remain responsible for auditing their event data.
  final TracerFilterErrorPolicy filterErrorPolicy;

  /// Receives personal-data-free HTTP and platform-lifecycle transitions.
  ///
  /// Listener exceptions are ignored. A later initialization replaces the listener
  /// for subsequent diagnostics. `sent` means only an HTTP response below 400.
  final TracerDeliveryListener? deliveryListener;

  /// Maximum number of breadcrumbs retained; the oldest are dropped first.
  /// Zero disables the Dart buffer. A negative value rejects collection startup
  /// with `invalid_max_breadcrumbs`, including release builds.
  final int maxBreadcrumbs;

  /// Whether to install a `FlutterError.onError` handler.
  final bool captureFlutterErrors;

  /// Whether to install a `PlatformDispatcher.instance.onError` handler.
  final bool capturePlatformDispatcherErrors;

  /// Whether to run the application inside a guarded zone so that uncaught
  /// asynchronous errors are captured.
  final bool captureZoneErrors;

  /// Whether automatically captured errors are reported as
  /// [TracerSeverity.fatal].
  ///
  /// This covers all three capture paths: `FlutterError.onError`,
  /// `PlatformDispatcher.instance.onError` and the guarded zone.
  ///
  /// Defaults to `false`, and the reason is worth stating plainly: **none of
  /// these errors terminate the process.** A Dart exception that nobody caught
  /// leaves the application running, which is exactly why the native SDKs never
  /// see it. On Android and iOS a fatal report counts against the crash-free
  /// metric, so reporting them as fatal would report crashes that did not
  /// happen and make the metric describe something other than crashes.
  ///
  /// Turn it on only if your team has deliberately decided that an unhandled
  /// Dart error should count as a crash for your product.
  final bool reportUnhandledErrorsAsFatal;

  /// Whether the verbatim stack-trace text is also written to the platform log
  /// buffer that Tracer attaches to the event.
  ///
  /// This is what keeps an obfuscated AOT trace recoverable: the addresses and
  /// the `build_id` header survive intact and can be fed to
  /// `flutter symbolize`. See `docs/symbolication.md`.
  final bool attachRawStackTraceAsLog;

  /// Byte budget for the verbatim stack trace written to the platform log.
  /// Zero means no limit. A negative value rejects startup with
  /// `invalid_max_raw_stack_trace_log_bytes`, including release builds.
  ///
  /// This is not a nicety. Android's log buffer is a **circular** 64 KiB
  /// buffer (`maxLogsLength` defaults to 65536, confirmed in the SDK
  /// bytecode): every byte written to it evicts an older one. A pathological
  /// Dart trace — a `StackOverflowError`, a deep async chain — can run to
  /// hundreds of kilobytes and would flush the entire breadcrumb trail out of
  /// the buffer, so the report would arrive with a stack trace and no context
  /// at all.
  ///
  /// Truncation keeps the *beginning* of the trace, because that is where the
  /// `build_id` header and the frames nearest the throw are, and it is what
  /// `flutter symbolize` needs.
  final int maxRawStackTraceLogBytes;

  /// Maximum number of parsed frames forwarded to the platform.
  /// Zero means no limit. A negative value rejects startup with
  /// `invalid_max_stack_frames`, including release builds.
  ///
  /// Caps the structured payload — the synthetic `StackTraceElement[]` on
  /// Android, the frame array in a Sentry envelope. The frames nearest the
  /// throw are kept.
  ///
  /// [DartStackTrace.raw] is never trimmed by this: the verbatim text is the
  /// only artefact an obfuscated trace can be decoded from, and it travels
  /// under [maxRawStackTraceLogBytes] instead.
  final int maxStackFrames;

  /// Whether the package logs its own diagnostics to the console.
  final bool debug;

  /// The environment that applies to this build.
  ///
  /// Defaults to `prod` in a release build and `dev` otherwise, so that
  /// nothing has to be passed for the usual case. Set [environment] to
  /// override — for a staging flavour, say.
  String get resolvedEnvironment =>
      environment ?? (kReleaseMode ? 'prod' : 'dev');

  /// Overrides the Tracer ingest endpoint, for proxying setups.
  final String? apiUrl;

  /// Custom keys applied as soon as the integration starts.
  final Map<String, String> initialCustomKeys;

  /// Returns a copy with the given fields replaced.
  /// Set [removeDeliveryListener] to detach the current listener.
  TracerOptions copyWith({
    String? appToken,
    String? iosAppToken,
    String? webAppToken,
    String? dsn,
    String? environment,
    String? release,
    String? dist,
    bool? isCollectionEnabled,
    TracerNativeInitialization? nativeInitialization,
    bool? preservePreviousReports,
    BeforeSendCallback? beforeSend,
    BeforeBreadcrumbCallback? beforeBreadcrumb,
    TracerFilterErrorPolicy? filterErrorPolicy,
    TracerDeliveryListener? deliveryListener,
    bool removeDeliveryListener = false,
    int? maxBreadcrumbs,
    bool? captureFlutterErrors,
    bool? capturePlatformDispatcherErrors,
    bool? captureZoneErrors,
    bool? reportUnhandledErrorsAsFatal,
    bool? attachRawStackTraceAsLog,
    int? maxRawStackTraceLogBytes,
    int? maxStackFrames,
    bool? debug,
    String? apiUrl,
    Map<String, String>? initialCustomKeys,
  }) {
    return TracerOptions(
      appToken: appToken ?? this.appToken,
      iosAppToken: iosAppToken ?? this.iosAppToken,
      webAppToken: webAppToken ?? this.webAppToken,
      dsn: dsn ?? this.dsn,
      environment: environment ?? this.environment,
      release: release ?? this.release,
      dist: dist ?? this.dist,
      isCollectionEnabled: isCollectionEnabled ?? this.isCollectionEnabled,
      nativeInitialization: nativeInitialization ?? this.nativeInitialization,
      preservePreviousReports:
          preservePreviousReports ?? this.preservePreviousReports,
      beforeSend: beforeSend ?? this.beforeSend,
      beforeBreadcrumb: beforeBreadcrumb ?? this.beforeBreadcrumb,
      filterErrorPolicy: filterErrorPolicy ?? this.filterErrorPolicy,
      deliveryListener: removeDeliveryListener
          ? null
          : deliveryListener ?? this.deliveryListener,
      maxBreadcrumbs: maxBreadcrumbs ?? this.maxBreadcrumbs,
      captureFlutterErrors: captureFlutterErrors ?? this.captureFlutterErrors,
      capturePlatformDispatcherErrors: capturePlatformDispatcherErrors ??
          this.capturePlatformDispatcherErrors,
      captureZoneErrors: captureZoneErrors ?? this.captureZoneErrors,
      reportUnhandledErrorsAsFatal:
          reportUnhandledErrorsAsFatal ?? this.reportUnhandledErrorsAsFatal,
      attachRawStackTraceAsLog:
          attachRawStackTraceAsLog ?? this.attachRawStackTraceAsLog,
      maxRawStackTraceLogBytes:
          maxRawStackTraceLogBytes ?? this.maxRawStackTraceLogBytes,
      maxStackFrames: maxStackFrames ?? this.maxStackFrames,
      debug: debug ?? this.debug,
      apiUrl: apiUrl ?? this.apiUrl,
      initialCustomKeys: initialCustomKeys ?? this.initialCustomKeys,
    );
  }

  /// Serializes the options that a platform implementation needs.
  ///
  /// Callbacks and listeners are Dart-only and are deliberately not included.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      // One value crosses the channel: the platform on the other side has no
      // use for the tokens of the other two.
      if (resolvedAppToken != null) 'appToken': resolvedAppToken,
      if (dsn != null) 'dsn': dsn,
      'environment': resolvedEnvironment,
      if (release != null) 'release': release,
      if (dist != null) 'dist': dist,
      'isCollectionEnabled': isCollectionEnabled,
      'nativeInitialization': nativeInitialization.name,
      'preservePreviousReports': preservePreviousReports,
      'maxBreadcrumbs': maxBreadcrumbs,
      'attachRawStackTraceAsLog': attachRawStackTraceAsLog,
      'maxRawStackTraceLogBytes': maxRawStackTraceLogBytes,
      'maxStackFrames': maxStackFrames,
      'debug': debug,
      if (apiUrl != null) 'apiUrl': apiUrl,
      if (initialCustomKeys.isNotEmpty) 'initialCustomKeys': initialCustomKeys,
    };
  }
}
