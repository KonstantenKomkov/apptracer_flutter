/// Observable queue, request and platform-lifecycle transitions.
enum TracerDeliveryState {
  /// Event was accepted into the current-session queue.
  queued,

  /// An HTTP server returned a status below 400; this is not console confirmation.
  sent,

  /// Another delivery attempt is scheduled.
  retry,

  /// An event was permanently removed without a successful response.
  dropped,

  /// Storage, scheduling, a platform call or lifecycle operation failed.
  failed,
}

/// Personal-data-free diagnostic transition.
///
/// Contains no event payload, error message, stack trace, DSN or application token.
/// `sent` describes only the transport response, never appearance in Tracer.
class TracerDeliveryDiagnostic {
  /// Creates a diagnostic value.
  ///
  /// The default backend and operation preserve the original HTTP-only model.
  const TracerDeliveryDiagnostic(
    this.state, {
    this.attempt = 0,
    required this.reason,
    this.backend = 'tracer-http',
    this.operation = 'delivery',
  });

  /// Transition kind.
  final TracerDeliveryState state;

  /// Attempt number, or zero for queue and lifecycle operations.
  final int attempt;

  /// Stable machine-readable reason without event or exception data.
  final String reason;

  /// Backend that emitted the transition, such as `android-native` or `sentry-sdk`.
  final String backend;

  /// Stable operation name, such as `delivery`, `recordError` or `stopCollection`.
  final String operation;
}

/// Receives optional delivery and lifecycle diagnostics.
typedef TracerDeliveryListener = void Function(
  TracerDeliveryDiagnostic diagnostic,
);
