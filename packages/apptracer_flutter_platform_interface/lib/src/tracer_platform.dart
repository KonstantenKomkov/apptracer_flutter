import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models/tracer_event.dart';
import 'models/tracer_options.dart';

/// The interface every platform implementation of the Tracer integration
/// implements.
///
/// Platform implementations must extend this class rather than implement it, so
/// that new members can be added without a breaking change. The
/// [PlatformInterface] token check enforces that.
///
/// ### Why [initialize] takes no `appRunner`
///
/// Running the host application inside a guarded zone is a Dart-side concern:
/// the zone, the handler chain and the "call `appRunner` exactly once" rule are
/// identical on every platform. Duplicating them per platform would be a way to
/// get them subtly wrong per platform. That logic therefore lives in
/// `Tracer.initialize` in the `apptracer_flutter` package, and this interface
/// stays a thin transport contract.
abstract class TracerPlatform extends PlatformInterface {
  /// Creates a platform implementation.
  TracerPlatform() : super(token: _token);

  static final Object _token = Object();

  static TracerPlatform _instance = UnsupportedTracerPlatform();

  /// The implementation registered for the current platform.
  ///
  /// Defaults to [UnsupportedTracerPlatform], which is inert. It is never
  /// `null`, so callers never have to null-check before use.
  static TracerPlatform get instance => _instance;

  /// Registers [value] as the implementation for the current platform.
  static set instance(TracerPlatform value) {
    PlatformInterface.verify(value, _token);
    _instance = value;
  }

  /// Whether collection is currently running.
  ///
  /// `false` before [initialize], after [stopCollection], when collection was
  /// disabled through [TracerOptions.isCollectionEnabled], and on any platform
  /// without an implementation.
  bool get isEnabled;

  /// Short identifier of the delivery backend, used in diagnostics — for
  /// example `android-native`, `ios-native`, `sentry-http` or `unsupported`.
  String get backendName;

  /// Whether breadcrumbs have to be mirrored into the platform log buffer as
  /// they happen.
  ///
  /// The native SDKs have no notion of a breadcrumb: the only way a trail
  /// reaches a report — including a *native* crash or an ANR, which the Dart
  /// side never sees — is if each entry was written to the native log when it
  /// occurred. Those implementations leave this `true`.
  ///
  /// A backend that carries breadcrumbs as structured data with the event,
  /// such as the Sentry protocol, sets this to `false`; mirroring there would
  /// send every breadcrumb twice.
  bool get mirrorsBreadcrumbsToLog => true;

  /// Whether this backend needs an `issueKey` synthesised when the caller did
  /// not supply one.
  ///
  /// Both native SDKs do: measured against a live project, Tracer keys an
  /// Android group on the top frame's class and method alone, so a
  /// `StateError` and a `TimeoutException` thrown from two closures in the
  /// same `build` land in one group; on iOS a Dart trace has no native
  /// addresses to group on at all. A backend that groups on richer data — the
  /// Sentry protocol, which carries the exception type and the full frame list
  /// — leaves this `false`. See [SyntheticIssueKey].
  bool get needsSyntheticIssueKey => false;

  /// Starts the platform SDK with [options].
  ///
  /// Implementations must not throw: a failure to start has to leave the
  /// integration disabled, not break the host application.
  Future<void> initialize(TracerOptions options);

  /// Stops collection and releases platform resources.
  ///
  /// Must be idempotent.
  Future<void> stopCollection();

  /// Delivers [event] to Tracer.
  Future<void> recordError(TracerEvent event);

  /// Appends [message] to the log buffer that Tracer attaches to events.
  Future<void> recordLog(String message);

  /// Sets a custom key/value pair on all subsequent events.
  Future<void> setCustomKey({required String key, required String value});

  /// Removes a previously set custom key.
  Future<void> removeCustomKey(String key);

  /// Associates subsequent events with [userId], or clears it when `null`.
  ///
  /// A user identifier is personal data. Nothing sets it automatically; call
  /// this only when you have a lawful basis to do so.
  Future<void> setUserId(String? userId);
}

/// The inert implementation used on platforms that have none.
///
/// Every method succeeds and does nothing. A single diagnostic line is printed
/// the first time the integration is used, so that the absence of reports is
/// discoverable without turning it into a crash.
class UnsupportedTracerPlatform extends TracerPlatform {
  /// Creates the inert implementation.
  UnsupportedTracerPlatform();

  bool _warned = false;

  @override
  bool get isEnabled => false;

  @override
  String get backendName => 'unsupported';

  void _warnOnce() {
    if (_warned) {
      return;
    }
    _warned = true;
    debugPrint(
      'apptracer_flutter: no Tracer implementation is registered for '
      '${defaultTargetPlatform.name}, so Dart errors are being discarded. '
      'Android and iOS are covered by the bundled native plugins. On any '
      'other target, register the pure-Dart transport yourself: '
      'TracerPlatform.instance = TracerHttpTracer(...) from '
      'package:apptracer_flutter_http, with TracerOptions.appToken set. '
      'See docs/platform-matrix.md.',
    );
  }

  @override
  Future<void> initialize(TracerOptions options) async => _warnOnce();

  @override
  Future<void> stopCollection() async {}

  @override
  Future<void> recordError(TracerEvent event) async => _warnOnce();

  @override
  Future<void> recordLog(String message) async {}

  @override
  Future<void> setCustomKey({
    required String key,
    required String value,
  }) async {}

  @override
  Future<void> removeCustomKey(String key) async {}

  @override
  Future<void> setUserId(String? userId) async {}
}
