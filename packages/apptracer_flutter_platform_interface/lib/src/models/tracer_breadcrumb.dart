import 'package:meta/meta.dart';

import 'tracer_severity.dart';

/// A single entry in the breadcrumb trail that is attached to reported events.
///
/// Breadcrumbs are buffered in Dart and delivered to the platform log storage
/// (`TracerCrashReport.log` on Android, the Tracer log provider on iOS, the
/// `logs` module in the Tracer JS SDK, and the Sentry `breadcrumbs` array for
/// the Sentry-protocol transport).
///
/// Breadcrumbs are free-form text written by the host application. Nothing is
/// collected automatically, so no personal data reaches Tracer unless the
/// application puts it there. See `docs/privacy.md`.
@immutable
class TracerBreadcrumb {
  /// Creates a breadcrumb.
  ///
  /// [timestamp] defaults to [DateTime.now] in UTC.
  TracerBreadcrumb({
    required this.message,
    this.category,
    this.level = TracerSeverity.info,
    this.data = const <String, String>{},
    DateTime? timestamp,
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc();

  /// Human-readable description of what happened.
  final String message;

  /// Optional grouping label, for example `navigation` or `http`.
  final String? category;

  /// Severity of the breadcrumb.
  final TracerSeverity level;

  /// Optional structured payload rendered next to [message].
  final Map<String, String> data;

  /// When the breadcrumb was recorded, always in UTC.
  final DateTime timestamp;

  /// Returns a copy with the given fields replaced.
  TracerBreadcrumb copyWith({
    String? message,
    String? category,
    TracerSeverity? level,
    Map<String, String>? data,
    DateTime? timestamp,
  }) {
    return TracerBreadcrumb(
      message: message ?? this.message,
      category: category ?? this.category,
      level: level ?? this.level,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Renders the breadcrumb as a single log line.
  ///
  /// This is the representation delivered to the Android and iOS log buffers,
  /// which are plain text.
  String toLogLine() {
    final buffer = StringBuffer()
      ..write(timestamp.toIso8601String())
      ..write(' [')
      ..write(level.wireName)
      ..write(']');
    if (category != null && category!.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(category);
    }
    buffer
      ..write(' | ')
      ..write(message);
    if (data.isNotEmpty) {
      final entries = data.entries.map((e) => '${e.key}=${e.value}').join(', ');
      buffer
        ..write(' {')
        ..write(entries)
        ..write('}');
    }
    return buffer.toString();
  }

  /// Serializes the breadcrumb for the method channel and the HTTP transport.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'message': message,
      if (category != null) 'category': category,
      'level': level.wireName,
      'timestamp': timestamp.toIso8601String(),
      if (data.isNotEmpty) 'data': data,
    };
  }

  /// Rebuilds a breadcrumb from [map] as produced by [toMap].
  static TracerBreadcrumb fromMap(Map<String, Object?> map) {
    final rawData = map['data'];
    return TracerBreadcrumb(
      message: (map['message'] as String?) ?? '',
      category: map['category'] as String?,
      level: TracerSeverity.fromWireName((map['level'] as String?) ?? '') ??
          TracerSeverity.info,
      data: rawData is Map
          ? rawData.map(
              (Object? k, Object? v) => MapEntry('$k', '$v'),
            )
          : const <String, String>{},
      timestamp: DateTime.tryParse((map['timestamp'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  @override
  String toString() => 'TracerBreadcrumb(${toLogLine()})';
}
