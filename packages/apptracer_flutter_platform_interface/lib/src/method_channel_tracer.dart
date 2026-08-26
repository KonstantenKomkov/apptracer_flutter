import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/tracer_event.dart';
import 'models/tracer_options.dart';
import 'tracer_platform.dart';

/// A [TracerPlatform] backed by a [MethodChannel].
///
/// Shared by the Android and iOS implementations, which differ only in the
/// native half. Every call is wrapped so that a platform-side failure degrades
/// to "collection is off" rather than propagating into the host application:
/// a crash reporter that crashes the app is worse than no crash reporter.
class MethodChannelTracer extends TracerPlatform {
  /// Creates an implementation talking over [channel].
  MethodChannelTracer({
    MethodChannel? channel,
    required this.backendName,
  }) : _channel = channel ?? const MethodChannel(defaultChannelName);

  /// The channel name shared with the native implementations.
  static const String defaultChannelName = 'ru.apptracer.flutter/tracer';

  final MethodChannel _channel;

  @override
  final String backendName;

  bool _enabled = false;
  bool _debug = false;

  @override
  bool get isEnabled => _enabled;

  /// Both native SDKs behind this channel group Dart errors too coarsely to
  /// tell two of them apart on their own. See [TracerPlatform.needsSyntheticIssueKey].
  @override
  bool get needsSyntheticIssueKey => true;

  /// The channel used by this implementation, exposed for tests.
  @visibleForTesting
  MethodChannel get channel => _channel;

  @override
  Future<void> initialize(TracerOptions options) async {
    _debug = options.debug;
    if (!options.isCollectionEnabled) {
      _enabled = false;
      return;
    }
    final started = await _invoke<bool>('initialize', options.toMap());
    _enabled = started ?? false;
  }

  @override
  Future<void> stopCollection() async {
    await _invoke<void>('stopCollection', null);
    _enabled = false;
  }

  @override
  Future<void> recordError(TracerEvent event) async {
    if (!_enabled) {
      return;
    }
    await _invoke<void>('recordError', event.toMap());
  }

  @override
  Future<void> recordLog(String message) async {
    if (!_enabled) {
      return;
    }
    await _invoke<void>('recordLog', <String, Object?>{'message': message});
  }

  @override
  Future<void> setCustomKey({
    required String key,
    required String value,
  }) async {
    if (!_enabled) {
      return;
    }
    await _invoke<void>(
      'setCustomKey',
      <String, Object?>{'key': key, 'value': value},
    );
  }

  @override
  Future<void> removeCustomKey(String key) async {
    if (!_enabled) {
      return;
    }
    await _invoke<void>('removeCustomKey', <String, Object?>{'key': key});
  }

  @override
  Future<void> setUserId(String? userId) async {
    if (!_enabled) {
      return;
    }
    await _invoke<void>('setUserId', <String, Object?>{'userId': userId});
  }

  Future<T?> _invoke<T>(String method, Object? arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // The Dart half of a federated plugin can be present while the native
      // half is not, for example in a unit test or on an unsupported host.
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
