import 'dart:convert';
import 'dart:io';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/services.dart';

/// Opt-in, process-local acceptance driver. Uses only inherited stdin/stdout;
/// there is no listener, token access or alternative telemetry transport.
Future<void> runLifecycleProbe() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final command = jsonDecode(line) as Map<String, dynamic>;
    try {
      switch (command['action']) {
        case 'start':
          await Tracer.startCollection(TracerOptions(
            dsn: Platform.environment['TRACER_MACOS_SENTRY_DSN'],
            release: '1.0.0',
            dist: '1',
            preservePreviousReports: command['preserve'] == true,
            initialCustomKeys: {
              'probe_run': Platform.environment['TRACER_RUN_ID'] ?? 'lifecycle'
            },
          ));
        case 'identify':
          final user = command['user'] as String;
          await Tracer.setUserId(user);
          await Tracer.setCustomKey(key: 'account_marker', value: user);
          Tracer.addBreadcrumb(TracerBreadcrumb(message: user));
        case 'capture':
          await Tracer.recordError(
              command['message'] as String, StackTrace.current);
        case 'stop':
          await Tracer.stopCollection();
        case 'clear':
          await Tracer.stopAndClearCollection();
        case 'crash':
          await const MethodChannel('apptracer_desktop_example')
              .invokeMethod<void>('nativeCrash');
        case 'state':
          break;
        default:
          throw ArgumentError('Unknown lifecycle action');
      }
      final state = await Tracer.getCollectionState();
      stdout.writeln('APPTRACER_RESULT ${jsonEncode({
            'id': command['id'],
            'state': state.state.name,
            'reason': state.reason,
            'enabled': Tracer.isEnabled,
          })}');
    } catch (error) {
      stdout.writeln('APPTRACER_RESULT ${jsonEncode({
            'id': command['id'],
            'error': error.runtimeType.toString(),
          })}');
    }
  }
}
