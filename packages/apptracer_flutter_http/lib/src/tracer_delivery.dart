import 'dart:async';

export 'package:apptracer_flutter_platform_interface/delivery_diagnostics.dart';

/// Bounds and timing for HTTP delivery and the owned event queue.
class TracerDeliveryPolicy {
  /// Creates immutable delivery limits.
  const TracerDeliveryPolicy({
    this.requestTimeout = const Duration(seconds: 10),
    this.maxAttempts = 5,
    this.initialBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
    this.maxRetryAfter = const Duration(minutes: 5),
    this.timeToLive = const Duration(hours: 24),
    this.maxEntries = 100,
    this.maxBytes = 1024 * 1024,
  })  : assert(maxAttempts > 0),
        assert(maxEntries > 0),
        assert(maxBytes > 0);

  /// Maximum duration of one HTTP request.
  final Duration requestTimeout;

  /// Total attempts, including the first one.
  final int maxAttempts;

  /// Base delay before the first retry.
  final Duration initialBackoff;

  /// Largest locally computed backoff.
  final Duration maxBackoff;

  /// Largest accepted server or computed retry delay.
  final Duration maxRetryAfter;

  /// Maximum age of a persisted event.
  final Duration timeToLive;

  /// Maximum number of queued events.
  final int maxEntries;

  /// Maximum combined UTF-8 payload size.
  final int maxBytes;
}

/// JSON-compatible persisted queue record.
typedef TracerQueueRecord = Map<String, Object?>;

/// Persistence for serialized queue records. Implementations must replace records atomically.
abstract class TracerQueueStore {
  /// Loads the last complete snapshot.
  Future<List<TracerQueueRecord>> load();

  /// Atomically replaces the snapshot.
  Future<void> save(List<TracerQueueRecord> records);

  /// Deletes the owned queue.
  Future<void> clear();
}

/// Session-only store, and the default for manually registered VM transports.
class TracerMemoryQueueStore implements TracerQueueStore {
  /// Current snapshot, exposed for lightweight VM tests.
  List<TracerQueueRecord> records = <TracerQueueRecord>[];

  @override
  Future<List<TracerQueueRecord>> load() async => records
      .map((record) => <String, Object?>{...record})
      .toList(growable: false);

  @override
  Future<void> save(List<TracerQueueRecord> records) async {
    this.records = records
        .map((record) => <String, Object?>{...record})
        .toList(growable: false);
  }

  @override
  Future<void> clear() async {
    records = <TracerQueueRecord>[];
  }
}
