import 'dart:convert';

import 'package:flutter/services.dart';

export 'src/aurora_tracer_platform.dart' show AuroraTracerPlatform;

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
    Map<String, String> initialKeys = const {},
    String? userId,
    bool replaceContext = false,
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
                'keys': initialKeys,
                'user': userId,
                'replace': replaceContext,
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

  static void cancelPendingStart() {
    ++_generation;
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
    if (message.contains('\x00')) throw ArgumentError('Embedded NUL in log');
    final generation = _generation;
    var offset = 0;
    // Even JSON control-character escapes fit in the 64 KiB worker packet.
    do {
      var end = offset + 8192;
      if (end >= message.length) {
        end = message.length;
      } else {
        final last = message.codeUnitAt(end - 1);
        if (last >= 0xd800 && last <= 0xdbff) end--;
      }
      await _call('log', {'value': message.substring(offset, end)});
      if (generation != _generation) return;
      offset = end;
    } while (offset < message.length);
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
