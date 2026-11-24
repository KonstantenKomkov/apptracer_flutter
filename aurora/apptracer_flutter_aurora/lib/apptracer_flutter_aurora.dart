import 'package:flutter/services.dart';

/// Diagnostics for the optional plugin shipped with the Aurora OS Flutter fork.
class AuroraTracer {
  static const _channel = MethodChannel('apptracer_flutter/aurora');

  /// Loads the packaged SDK and checks the system crash handler.
  static Future<Map<String, Object?>> probe() async {
    final result = await _channel.invokeMapMethod<String, Object?>('probe');
    if (result == null) throw StateError('Empty Aurora SDK probe result');
    return result;
  }
}
