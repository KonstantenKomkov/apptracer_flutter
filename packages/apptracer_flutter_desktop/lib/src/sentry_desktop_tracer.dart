import 'dart:async';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'event_mapping.dart';
import 'macos_lifecycle.dart';
import 'sdk_configuration.dart';

/// Official Sentry SDK transport for desktop. Native acceptance is pending.
///
/// Install explicitly before Tracer.initialize. Never initialize Sentry elsewhere
/// in the same process. Tracer retains ownership of appRunner and error handlers.
/// On macOS stop cancels native delivery and revokes replay; clear also deletes
/// this adapter's queue. A new process is required before collection can resume.
/// Native purge on Windows remains unsupported pending platform acceptance.
class SentryDesktopTracer extends TracerPlatform {
  /// Creates an inert adapter; the SDK starts only after collection is allowed.
  SentryDesktopTracer();

  /// Registers the optional macOS plugin without starting the native SDK.
  static void registerWith() {
    TracerPlatform.instance = SentryDesktopTracer();
  }

  static SentryDesktopTracer? _owner;
  ObservedSdkOptions? _sdkOptions;
  bool _enabled = false;
  bool _attemptedNativeStart = false;
  bool _closeFailed = false;
  int _generation = 0;
  Future<void> _tail = Future<void>.value();
  TracerCollectionResult _state =
      const TracerCollectionResult(TracerCollectionState.disabled);

  @override
  bool get isEnabled => _enabled;

  @override
  String get backendName => 'sentry-sdk';

  // Filtered Tracer breadcrumbs are mirrored as native log breadcrumbs.
  // Dart events replace the SDK scope trail with their filtered structured trail.
  @override
  bool get mirrorsBreadcrumbsToLog => true;

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<void> initialize(TracerOptions options) async {
    if (options.nativeInitialization == TracerNativeInitialization.deferred ||
        !options.isCollectionEnabled) {
      if (_attemptedNativeStart) await stopCollection();
      return;
    }
    await startCollection(options);
  }

  @override
  Future<TracerCollectionResult> startCollection(TracerOptions options) {
    if (!options.isCollectionEnabled) {
      return stopCollection().then((_) => _state);
    }
    final generation = _generation;
    return _serial(() async {
      if (generation != _generation) return _state;
      if (_enabled || _closeFailed) return _state;
      if (_attemptedNativeStart) {
        return _state = const TracerCollectionResult(
            TracerCollectionState.restartRequired,
            reason: 'desktop_restart_required');
      }
      if (kIsWeb ||
          (defaultTargetPlatform != TargetPlatform.macOS &&
              defaultTargetPlatform != TargetPlatform.windows)) {
        return _state = const TracerCollectionResult(
            TracerCollectionState.unsupported,
            reason: 'desktop_platform_required');
      }
      if (!_validDsn(options.dsn)) {
        return _state = const TracerCollectionResult(
            TracerCollectionState.disabled,
            reason: 'invalid_sentry_dsn');
      }
      if (_owner != null || Sentry.isEnabled) {
        return _state = const TracerCollectionResult(
            TracerCollectionState.error,
            reason: 'sentry_already_owned');
      }
      _owner = this;
      _attemptedNativeStart = true;
      final sdk = _sdkOptions = ObservedSdkOptions();
      try {
        await SentryFlutter.init((sdk) {
          configureDesktopSdk(sdk, options);
          sdk.beforeSend = (event, hint) {
            final source = hint.get('apptracer.event');
            if (!_enabled ||
                generation != _generation ||
                source is! TracerEvent) {
              return null;
            }
            return restoreFilteredFields(event, source);
          };
          // Only recordLog supplies native breadcrumbs; automatic integrations
          // are disabled. Tracer invokes the user's breadcrumb filter first.
        },
            // Pinned SDK injection is necessary to observe errors the SDK
            // otherwise swallows with debug=false; this is not a fake transport.
            // ignore: invalid_use_of_internal_member
            options: sdk);
        final integration = defaultTargetPlatform == TargetPlatform.macOS
            ? 'apptracerMacOSLifecycle'
            : 'nativeSdkIntegration';
        if (!Sentry.isEnabled ||
            sdk.failures != 0 ||
            !sdk.sdk.integrations.contains(integration)) {
          throw StateError('native_start_not_confirmed');
        }
        if (generation != _generation) {
          await _close();
          return _state;
        }
        _enabled = true;
        return _state =
            const TracerCollectionResult(TracerCollectionState.enabled);
      } catch (_) {
        _enabled = false;
        await _close();
        return _state = const TracerCollectionResult(
            TracerCollectionState.error,
            reason: 'sentry_initialization_failed');
      }
    });
  }

  static bool _validDsn(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isEmpty ||
        uri.userInfo.contains(':') ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.isEmpty ||
        uri.pathSegments.last.isEmpty) {
      return false;
    }
    // Plain HTTP is only useful for a local acceptance receiver.
    return uri.scheme == 'https' ||
        (uri.scheme == 'http' &&
            const ['localhost', '127.0.0.1', '::1'].contains(uri.host));
  }

  Future<void> _close() async {
    if (_closeFailed || (_owner != null && !identical(_owner, this))) return;
    if (_owner == null) {
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        try {
          _state = await MacOSLifecycle.invoke('closeNativeSdk');
        } catch (_) {
          _closeFailed = true;
          _state = const TracerCollectionResult(TracerCollectionState.error,
              reason: 'sentry_close_failed');
        }
      }
      return;
    }
    final sdk = _sdkOptions;
    final failures = sdk?.failures;
    try {
      // Cancel the native session BEFORE Dart/Cocoa close can flush its queue.
      final nativeState = defaultTargetPlatform == TargetPlatform.macOS
          ? await MacOSLifecycle.invoke('closeNativeSdk')
          : null;
      await Sentry.close();
      if (sdk?.failures != failures) throw StateError('native_close_failed');
      _state = nativeState ??
          const TracerCollectionResult(TracerCollectionState.restartRequired,
              reason: 'native_purge_unverified');
    } catch (_) {
      _closeFailed = true;
      _state = const TracerCollectionResult(TracerCollectionState.error,
          reason: 'sentry_close_failed');
    }
    // Keep ownership after any native attempt. A new adapter must not bypass
    // the restart requirement and resend the previous account's persisted data.
  }

  @override
  Future<void> stopCollection() {
    _enabled = false;
    ++_generation;
    return _serial(_close);
  }

  @override
  Future<TracerCollectionResult> stopAndClearCollection() {
    _enabled = false;
    ++_generation;
    // Close and purge must occupy ONE queue slot. Otherwise a prestart clear
    // can yield to a later start, then clear its freshly enabled native SDK.
    return _serial(() async {
      await _close();
      if (_state.state == TracerCollectionState.error) return _state;
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        if (_owner != null && !identical(_owner, this)) {
          return _state = const TracerCollectionResult(
              TracerCollectionState.error,
              reason: 'sentry_already_owned');
        }
        try {
          return _state = await MacOSLifecycle.invoke('clearNativeSdk');
        } catch (_) {
          _closeFailed = true;
          return _state = const TracerCollectionResult(
              TracerCollectionState.error,
              reason: 'native_cleanup_failed');
        }
      }
      return _state = const TracerCollectionResult(
          TracerCollectionState.unsupported,
          reason: 'native_purge_not_implemented');
    });
  }

  @override
  Future<TracerCollectionResult> getCollectionState() async => _state;

  Future<void> _whileEnabled(Future<void> Function() action) {
    // Calls made while init is pending must not become data in a later session.
    if (!_enabled) return Future<void>.value();
    final generation = _generation;
    return _serial(() async {
      if (!_enabled || generation != _generation) return;
      try {
        await action();
      } catch (_) {/* Diagnostics must not break the app. */}
    });
  }

  @override
  Future<void> recordError(TracerEvent event) => _whileEnabled(() async {
        await Sentry.captureEvent(toSentryEvent(event),
            hint: Hint.withMap({'apptracer.event': event}));
      });

  @override
  Future<void> recordLog(String message) => _whileEnabled(() async {
        await Sentry.addBreadcrumb(
            Breadcrumb(message: message, category: 'apptracer'));
      });

  @override
  Future<void> setCustomKey({required String key, required String value}) =>
      _whileEnabled(() async {
        await Sentry.configureScope((scope) => scope.setTag(key, value));
      });

  @override
  Future<void> removeCustomKey(String key) => _whileEnabled(() async {
        await Sentry.configureScope((scope) => scope.removeTag(key));
      });

  @override
  Future<void> setUserId(String? userId) => _whileEnabled(() async {
        await Sentry.configureScope((scope) =>
            scope.setUser(userId == null ? null : SentryUser(id: userId)));
      });
}
