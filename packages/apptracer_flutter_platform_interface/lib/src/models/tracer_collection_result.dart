/// Native transport state, distinct from permission to emit Dart events.
enum TracerCollectionState {
  /// The transport is collecting.
  enabled,

  /// The transport is off.
  disabled,

  /// Collection cannot restart in this process.
  restartRequired,

  /// The platform cannot implement the requested operation.
  unsupported,

  /// Start, observation, stop or required cleanup failed.
  error,
}

/// Result of a lifecycle operation. An error never grants collection.
class TracerCollectionResult {
  /// Creates an operation result.
  const TracerCollectionResult(this.state, {this.reason});

  /// Transport state reported by the platform.
  final TracerCollectionState state;

  /// Stable diagnostic code, not a consent decision.
  final String? reason;

  /// Whether this result confirms running collection.
  bool get isEnabled => state == TracerCollectionState.enabled;

  /// Decodes a native method-channel response.
  factory TracerCollectionResult.fromMap(Map<Object?, Object?> map) {
    final name = map['state'];
    final state = TracerCollectionState.values.where((s) => s.name == name);
    if (state.isEmpty) {
      return const TracerCollectionResult(
        TracerCollectionState.error,
        reason: 'invalid_native_result',
      );
    }
    return TracerCollectionResult(state.single,
        reason: map['reason'] as String?);
  }
}

/// Automatic preserves existing native integrations. Deferred requires the
/// platform's build-time setup as well as an explicit startCollection call.
enum TracerNativeInitialization {
  /// Preserves the existing platform startup behavior.
  automatic,

  /// Bootstraps without starting transport; requires platform support.
  deferred,
}
