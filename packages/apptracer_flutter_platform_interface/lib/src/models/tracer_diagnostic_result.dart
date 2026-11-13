/// Outcome of an optional diagnostic command, not a delivery acknowledgement.
enum TracerDiagnosticState {
  /// The native void method returned; the SDK may still discard the sample.
  invoked,

  /// Collection or the requested operation is disabled.
  disabled,

  /// The platform, module or required host configuration is unavailable.
  unsupported,

  /// The native command failed.
  error,
}

/// Result of an explicitly requested optional native diagnostic.
class TracerDiagnosticResult {
  /// Creates a result with an optional machine-readable reason.
  const TracerDiagnosticResult(this.state, {this.reason});

  /// Decodes a platform response, failing closed for malformed results.
  factory TracerDiagnosticResult.fromMap(Map<Object?, Object?> map) {
    for (final state in TracerDiagnosticState.values) {
      if (map['state'] == state.name) {
        return TracerDiagnosticResult(state,
            reason: map['reason'] is String ? map['reason']! as String : null);
      }
    }
    return const TracerDiagnosticResult(TracerDiagnosticState.error,
        reason: 'invalid_native_result');
  }

  /// Command outcome; invoked does not establish capture or upload success.
  final TracerDiagnosticState state;

  /// Platform-specific detail, without diagnostic payloads.
  final String? reason;
}
