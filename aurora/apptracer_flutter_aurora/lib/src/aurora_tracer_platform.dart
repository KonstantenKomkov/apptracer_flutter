import 'dart:async';
import 'dart:io';

import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:sentry/sentry.dart';

import '../apptracer_flutter_aurora.dart' show AuroraTracer;
import 'event_mapping.dart';

class AuroraTracerPlatform extends TracerPlatform {
  static void registerWith() {
    if (TracerPlatform.instance is! AuroraTracerPlatform) {
      TracerPlatform.instance = AuroraTracerPlatform();
    }
  }

  static const _disabled = TracerCollectionResult(
    TracerCollectionState.disabled,
  );
  static const _enabled = TracerCollectionResult(TracerCollectionState.enabled);
  TracerCollectionResult _state = _disabled;
  TracerOptions? _options;
  SentryClient? _sentry;
  _EventClient? _http;
  String? _user;
  final _keys = <String, String>{};
  int _generation = 0;
  Future<void> _tail = Future.value();

  @override
  bool get isEnabled => _state.isEnabled;
  @override
  String get backendName => 'aurora-native';

  static bool _sameScope(TracerOptions a, TracerOptions b) =>
      a.resolvedAppToken == b.resolvedAppToken &&
      a.auroraAccountScope == b.auroraAccountScope &&
      a.dsn == b.dsn;

  @override
  void configureDelivery(
    TracerOptions options, {
    bool activateListener = true,
  }) {
    super.configureDelivery(options, activateListener: activateListener);
    final previous = _options;
    if (previous != null && isEnabled && !_sameScope(previous, options)) {
      // Also revoke a running account when the new bootstrap is deferred.
      unawaited(stopAndClearCollection());
    }
  }

  void _diagnose(String operation, String reason, {bool sent = false}) {
    TracerDeliveryDiagnostic(
      sent ? TracerDeliveryState.sent : TracerDeliveryState.failed,
      operation: operation,
      backend: backendName,
      reason: reason,
    ).notify(deliveryListener);
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<void> initialize(TracerOptions options) async {
    configureDelivery(options);
    if (!options.isCollectionEnabled ||
        options.nativeInitialization == TracerNativeInitialization.deferred) {
      if (_options != null) await stopAndClearCollection();
      return;
    }
    await startCollection(options);
  }

  static bool _validDsn(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.host.isNotEmpty &&
        uri.userInfo.isNotEmpty &&
        !uri.userInfo.contains(':') &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.last.isNotEmpty &&
        (uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(uri.host)));
  }

  Future<void> _closeClient() async {
    final client = _sentry;
    _sentry = null;
    _http?.close();
    _http = null;
    if (client != null) await client.close();
  }

  Future<String> _startNative(
    TracerOptions options, {
    required bool preserve,
    bool replace = false,
  }) => AuroraTracer.startCollection(
    appToken: options.resolvedAppToken!,
    accountScope: options.auroraAccountScope ?? 'no-replay',
    versionName: options.release ?? 'unspecified',
    versionCode: int.tryParse(options.dist ?? '') ?? 0,
    preservePreviousReports: preserve,
    initialKeys: _keys,
    userId: _user,
    replaceContext: replace,
  );

  @override
  Future<TracerCollectionResult> startCollection(TracerOptions options) {
    if (!options.isCollectionEnabled) return stopAndClearCollection();
    configureDelivery(options);
    final epoch = _generation;
    return _serial(() async {
      if (epoch != _generation) return _disabled;
      final old = _options;
      if (old != null && isEnabled && _sameScope(old, options)) return _state;
      try {
        if (old != null) {
          await _closeClient();
          await AuroraTracer.stopAndClearCollection();
        }
        if (epoch != _generation) return _disabled;
        final dsn = options.dsn?.trim() ?? '';
        if (options.resolvedAppToken?.trim().isNotEmpty != true ||
            (options.preservePreviousReports &&
                options.auroraAccountScope?.trim().isNotEmpty != true) ||
            (dsn.isNotEmpty && !_validDsn(dsn))) {
          throw PlatformException(code: 'invalid_aurora_configuration');
        }
        _user = null;
        _keys
          ..clear()
          ..addAll(options.initialCustomKeys);
        _options = options;
        await _startNative(
          options,
          preserve: options.preservePreviousReports && old == null,
        );
        if (epoch != _generation) return _disabled;
        if (dsn.isNotEmpty) {
          final httpClient = _EventClient((status) {
            if (epoch != _generation || !isEnabled) return;
            _diagnose(
              'recordError',
              status == null ? 'transport_error' : 'http_$status',
              sent: status != null && status >= 200 && status < 300,
            );
          });
          _http = httpClient;
          final config = SentryOptions()
            ..dsn = dsn
            ..release = options.release
            ..dist = options.dist
            ..environment = options.environment
            ..httpClient = httpClient
            ..sendDefaultPii = false
            ..sendClientReports = false;
          _sentry = SentryClient(config);
        }
        return _state = _enabled;
      } catch (error) {
        if (epoch != _generation) return _disabled;
        await _closeClient();
        _options = null;
        _keys.clear();
        _user = null;
        try {
          await AuroraTracer.stopAndClearCollection();
        } catch (_) {
          return _state = const TracerCollectionResult(
            TracerCollectionState.error,
            reason: 'aurora_cleanup_failed',
          );
        }
        return _state = TracerCollectionResult(
          TracerCollectionState.error,
          reason: error is PlatformException
              ? error.code
              : 'aurora_start_failed',
        );
      }
    });
  }

  @override
  void cancelPendingStart() {
    ++_generation;
    AuroraTracer.cancelPendingStart();
  }

  @override
  Future<TracerCollectionResult> stopAndClearCollection() {
    cancelPendingStart();
    _state = _disabled;
    _http?.close();
    // Dispatch withdrawal immediately, even when context replacement is pending.
    final stop = AuroraTracer.stopAndClearCollection().then<String?>(
      (_) => null,
      onError: (Object _) => 'aurora_cleanup_failed',
    );
    return _serial(() async {
      _options = null;
      _keys.clear();
      _user = null;
      await _closeClient();
      final failure = await stop;
      return _state = failure == null
          ? _disabled
          : TracerCollectionResult(
              TracerCollectionState.error,
              reason: failure,
            );
    });
  }

  @override
  Future<void> stopCollection() async {
    await stopAndClearCollection();
  }

  @override
  Future<TracerCollectionResult> getCollectionState() async {
    if (!isEnabled) return _state;
    final epoch = _generation;
    try {
      await AuroraTracer.isUploading();
    } catch (_) {
      if (epoch == _generation) {
        await stopAndClearCollection();
        return _state = const TracerCollectionResult(
          TracerCollectionState.error,
          reason: 'worker_unavailable',
        );
      }
    }
    return _state;
  }

  @override
  Future<void> recordError(TracerEvent event) async {
    final epoch = _generation;
    await _tail;
    if (!isEnabled || epoch != _generation) return;
    final client = _sentry;
    if (client == null) {
      _diagnose('recordError', 'dart_dsn_missing');
      return;
    }
    final payload = toSentryEvent(event);
    if (_user != null) payload.user = SentryUser(id: _user);
    await client.captureEvent(payload);
  }

  Future<void> _context(Future<void> Function(TracerOptions) action) {
    final epoch = _generation;
    return _serial(() async {
      final options = _options;
      if (!isEnabled || options == null || epoch != _generation) return;
      try {
        await action(options);
      } catch (_) {
        // Stop collection if a requested identity/key change cannot be applied.
        if (epoch == _generation) {
          _state = const TracerCollectionResult(
            TracerCollectionState.error,
            reason: 'aurora_context_failed',
          );
          await _closeClient();
          await AuroraTracer.stopAndClearCollection();
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> recordLog(String message) {
    final epoch = _generation;
    return _serial(() async {
      if (isEnabled && epoch == _generation) await AuroraTracer.log(message);
    });
  }

  @override
  Future<void> setCustomKey({required String key, required String value}) =>
      _context((_) async {
        if (_keys[key] == value) return;
        await AuroraTracer.setKey(key, value);
        _keys[key] = value;
      });

  @override
  Future<void> removeCustomKey(String key) => _context((options) async {
    if (_keys.remove(key) != null)
      await _startNative(options, preserve: true, replace: true);
  });

  @override
  Future<void> setUserId(String? userId) => _context((options) async {
    if (_user == userId) return;
    _user = userId;
    await _startNative(options, preserve: false, replace: true);
  });
}

class _EventClient extends http.BaseClient {
  _EventClient(this.report);
  final void Function(int?) report;
  final _client = IOClient(HttpClient());

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.followRedirects = false;
    try {
      final response = await _client.send(request);
      report(response.statusCode);
      return response;
    } catch (_) {
      report(null);
      rethrow;
    }
  }

  @override
  void close() => _client.close();
}
