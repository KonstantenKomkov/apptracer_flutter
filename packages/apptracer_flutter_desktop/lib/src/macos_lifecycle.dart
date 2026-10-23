import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Native ownership is separate from sentry_flutter's envelope/scope bridge.
class MacOSLifecycle {
  static final _owner = SentryId.newId().toString();

  /// Channel owned by this adapter's Cocoa lifecycle bridge.
  static const channel = MethodChannel('apptracer_flutter_desktop/lifecycle');

  /// Awaits native acknowledgement and rejects explicit native failures.
  static Future<TracerCollectionResult> invoke(String method,
      [Map<String, Object?>? arguments]) async {
    final result = await channel.invokeMapMethod<Object?, Object?>(method, {
      ...?arguments,
      'owner': _owner,
    });
    if (result == null) throw StateError('missing_native_lifecycle_result');
    final state = TracerCollectionResult.fromMap(result);
    if (state.state == TracerCollectionState.error) {
      throw StateError(state.reason ?? 'native_lifecycle_failed');
    }
    return state;
  }
}

/// Uses public Cocoa start/options while official sentry_flutter still handles
/// envelope serialization, scope synchronization and native debug images.
class MacOSLifecycleIntegration implements Integration<SentryFlutterOptions> {
  /// Creates a lifecycle integration for the authorized collection options.
  MacOSLifecycleIntegration(this.tracer);

  /// Includes the explicit policy for reports from previous processes.
  final TracerOptions tracer;

  @override
  Future<void> call(Hub hub, SentryFlutterOptions options) async {
    final result = await MacOSLifecycle.invoke('initNativeSdk', {
      'dsn': options.dsn,
      'release': options.release,
      'environment': options.environment,
      'dist': options.dist,
      'maxBreadcrumbs': options.maxBreadcrumbs,
      'maxCacheItems': options.maxCacheItems,
      'preservePreviousReports': tracer.preservePreviousReports,
    });
    if (!result.isEnabled) throw StateError('native_start_not_confirmed');
    options.sdk.addIntegration('apptracerMacOSLifecycle');
  }

  @override
  Future<void> close() async {
    await MacOSLifecycle.invoke('closeNativeSdk');
  }
}
