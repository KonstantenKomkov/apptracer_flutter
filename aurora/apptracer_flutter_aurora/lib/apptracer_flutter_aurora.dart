import 'dart:convert';

import 'package:flutter/services.dart';

/// Consent-controlled native Tracer adapter for the Aurora OS Flutter fork.
class AuroraTracer {
  static const _channel = MethodChannel('apptracer_flutter/aurora');

  static int _generation = 0;

  /// Loads the packaged SDK and checks the system crash handler.
  static Future<Map<String, Object?>> probe() async {
    final result = await _channel.invokeMapMethod<String, Object?>('probe');
    if (result == null) throw StateError('Empty Aurora SDK probe result');
    return result;
  }

  /// Starts native collection after the caller has obtained consent.
  /// Supply the same opaque [accountScope] on restart to replay approved reports.
  static Future<String> startCollection({
    required String appToken,
    required String accountScope,
    required String versionName,
    required int versionCode,
    bool preservePreviousReports = false,
  }) async {
    final generation = ++_generation;
    final prepared =
        jsonDecode(
              await _call('prepare', {
                'token': appToken,
                'account': accountScope,
                'version': versionName,
                'build': versionCode,
                'preserve': preservePreviousReports,
              }),
            )
            as Map<String, dynamic>;
    if (generation != _generation)
      throw PlatformException(code: 'start_superseded');
    if (prepared['ticket'] case final String ticket) {
      await _call('activate', {'ticket': ticket});
    }
    if (generation != _generation)
      throw PlatformException(code: 'start_superseded');
    return prepared['result'] as String;
  }

  /// Revokes replay, stops the isolated SDK process and clears local crash data.
  static Future<void> stopAndClearCollection() async {
    ++_generation;
    await _call('withdraw', {});
  }

  /// Reports SDK upload activity. An idle worker can still have offline reports.
  static Future<bool> isUploading() async =>
      await _call('status', {}) == 'uploading';

  static Future<void> log(String message) async {
    await _call('log', {'value': message});
  }

  static Future<void> setKey(String key, String value) async {
    await _call('key', {'key': key, 'value': value});
  }

  static Future<String> _call(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final result = await _channel.invokeMethod<String>(
      method,
      jsonEncode(arguments),
    );
    if (result == null) throw StateError('Empty Aurora collection result');
    return result;
  }
}
