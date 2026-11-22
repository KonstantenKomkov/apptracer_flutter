import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/tracer_event.dart';
import 'models/tracer_diagnostic_result.dart';
import 'models/tracer_collection_result.dart';
import 'models/tracer_options.dart';
import 'native_contract.dart';
import 'pigeon/tracer_api.dart';
import 'tracer_platform.dart';

/// A [TracerPlatform] backed by the generated native contract.
class MethodChannelTracer extends TracerPlatform {
  /// Creates an implementation. [nativeApi] is intended for contract tests.
  MethodChannelTracer({
    MethodChannel? channel,
    TracerNativeApi? nativeApi,
    required this.backendName,
  })  : _channel = channel ?? const MethodChannel(defaultChannelName),
        _explicitLegacyChannel = channel != null,
        _native = nativeApi ?? TracerNativeApi();

  /// Legacy channel retained for independent package-version compatibility.
  static const String defaultChannelName = 'ru.apptracer.flutter/tracer';

  final MethodChannel _channel;
  final TracerNativeApi _native;
  final bool _explicitLegacyChannel;

  @override
  final String backendName;

  bool _enabled = false;
  bool _debug = false;
  int _generation = 0;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get needsSyntheticIssueKey => true;

  /// Legacy channel used with older native implementations.
  @visibleForTesting
  MethodChannel get channel => _channel;

  @override
  Future<void> initialize(TracerOptions options) async {
    _debug = options.debug;
    final generation = ++_generation;
    if (!options.isCollectionEnabled) {
      _enabled = false;
      return;
    }
    final started = await _invoke<bool>('initialize',
        () => _native.initialize(nativeOptions(options)), options.toMap);
    if (generation == _generation) _enabled = started ?? false;
  }

  @override
  Future<void> stopCollection() async {
    ++_generation;
    _enabled = false;
    await _invoke<void>('stopCollection', _native.stopCollection);
  }

  @override
  Future<TracerCollectionResult> pauseCollection() {
    ++_generation;
    _enabled = false;
    return _lifecycle('pauseCollection', _native.pauseCollection);
  }

  @override
  Future<TracerCollectionResult> resumeCollection() async {
    final generation = ++_generation;
    final result =
        await _lifecycle('resumeCollection', _native.resumeCollection);
    if (generation != _generation) {
      return const TracerCollectionResult(TracerCollectionState.disabled,
          reason: 'superseded');
    }
    _enabled = result.isEnabled;
    return result;
  }

  @override
  Future<TracerDiagnosticResult> runHeapDump({required String tag}) =>
      _diagnostic('runHeapDump', () => _native.runHeapDump(tag),
          arguments: {'tag': tag});

  @override
  Future<TracerDiagnosticResult> runDiskUsage() =>
      _diagnostic('runDiskUsage', _native.runDiskUsage);

  @override
  Future<TracerDiagnosticResult> setHeapDumpEnabled(bool enabled) =>
      _diagnostic(
          'setHeapDumpEnabled', () => _native.setHeapDumpEnabled(enabled),
          arguments: {'enabled': enabled}, allowDisabled: !enabled);

  Future<TracerDiagnosticResult> _diagnostic(
    String method,
    Future<NativeDiagnosticResult> Function() call, {
    Object? arguments,
    bool allowDisabled = false,
  }) async {
    if (!_enabled && !allowDisabled) {
      return const TracerDiagnosticResult(TracerDiagnosticState.disabled,
          reason: 'collection_disabled');
    }
    final generation = _generation;
    try {
      final result = await _withLegacy(
        () async => publicDiagnosticResult(await call()),
        () async => TracerDiagnosticResult.fromMap(await _channel
                .invokeMapMethod<Object?, Object?>(method, arguments) ??
            const {}),
      );
      if (generation != _generation) {
        return const TracerDiagnosticResult(TracerDiagnosticState.disabled,
            reason: 'superseded');
      }
      return result;
    } on MissingPluginException {
      return const TracerDiagnosticResult(TracerDiagnosticState.unsupported,
          reason: 'native_operation_missing');
    } catch (_) {
      return const TracerDiagnosticResult(TracerDiagnosticState.error,
          reason: 'native_diagnostic_failed');
    }
  }

  @override
  Future<TracerCollectionResult> startCollection(TracerOptions options) async {
    _debug = options.debug;
    final generation = ++_generation;
    if (!options.isCollectionEnabled) {
      _enabled = false;
      return const TracerCollectionResult(TracerCollectionState.disabled);
    }
    final result = await _lifecycle('startCollection',
        () => _native.startCollection(nativeOptions(options)), options.toMap);
    if (generation != _generation) {
      return const TracerCollectionResult(TracerCollectionState.disabled,
          reason: 'superseded');
    }
    _enabled = result.isEnabled;
    return result;
  }

  @override
  Future<TracerCollectionResult> stopAndClearCollection() {
    ++_generation;
    _enabled = false;
    return _lifecycle('stopAndClearCollection', _native.stopAndClearCollection);
  }

  @override
  Future<TracerCollectionResult> getCollectionState() async {
    final generation = _generation;
    final result =
        await _lifecycle('getCollectionState', _native.getCollectionState);
    if (!result.isEnabled && generation == _generation) _enabled = false;
    return result;
  }

  Future<TracerCollectionResult> _lifecycle(
      String method, Future<NativeCollectionResult> Function() call,
      [Object? Function()? arguments]) async {
    try {
      return await _withLegacy(() async => publicCollectionResult(await call()),
          () async {
        final result = await _channel.invokeMapMethod<Object?, Object?>(
            method, arguments?.call());
        if (result == null) {
          return const TracerCollectionResult(TracerCollectionState.error,
              reason: 'invalid_native_result');
        }
        return TracerCollectionResult.fromMap(result);
      });
    } on MissingPluginException {
      return const TracerCollectionResult(TracerCollectionState.unsupported,
          reason: 'native_operation_missing');
    } catch (error) {
      return TracerCollectionResult(TracerCollectionState.error,
          reason: '$method: $error');
    }
  }

  @override
  Future<void> recordError(TracerEvent event) async {
    if (!_enabled) return;
    await _invoke<void>('recordError',
        () => _native.recordError(nativeEvent(event)), event.toMap);
  }

  @override
  Future<void> recordLog(String message) async {
    if (!_enabled) return;
    await _invoke<void>('recordLog', () => _native.recordLog(message),
        () => {'message': message});
  }

  @override
  Future<void> setCustomKey(
      {required String key, required String value}) async {
    if (!_enabled) return;
    await _invoke<void>('setCustomKey', () => _native.setCustomKey(key, value),
        () => {'key': key, 'value': value});
  }

  @override
  Future<void> removeCustomKey(String key) async {
    if (!_enabled) return;
    await _invoke<void>('removeCustomKey', () => _native.removeCustomKey(key),
        () => {'key': key});
  }

  @override
  Future<void> setUserId(String? userId) async {
    if (!_enabled) return;
    await _invoke<void>(
        'setUserId', () => _native.setUserId(userId), () => {'userId': userId});
  }

  Future<T> _withLegacy<T>(
      Future<T> Function() typed, Future<T> Function() legacy) async {
    if (!_explicitLegacyChannel) {
      try {
        return await typed();
      } on PlatformException catch (error) {
        // A null Pigeon reply means the host has no handler for this operation.
        if (error.code != 'channel-error') rethrow;
      }
    }
    return legacy();
  }

  Future<T?> _invoke<T>(String method, Future<T> Function() call,
      [Object? Function()? arguments]) async {
    try {
      return await _withLegacy<T?>(
          call, () => _channel.invokeMethod<T>(method, arguments?.call()));
    } on MissingPluginException {
      _enabled = false;
      if (_debug) {
        debugPrint(
          'apptracer_flutter: native implementation is missing, '
          'collection disabled.',
        );
      }
      return null;
    } on PlatformException catch (error) {
      if (_debug) {
        debugPrint('apptracer_flutter: $method failed: ${error.message}');
      }
      return null;
    }
  }
}
