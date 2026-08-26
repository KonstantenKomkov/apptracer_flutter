import 'package:meta/meta.dart';

import 'dart_stack_trace.dart';
import 'tracer_breadcrumb.dart';
import 'tracer_severity.dart';

/// A Dart-side error that is about to be delivered to Tracer.
///
/// This is the value handed to [TracerOptions.beforeSend], which may edit it,
/// or return `null` to drop the event entirely.
@immutable
class TracerEvent {
  /// Creates an event.
  TracerEvent({
    required this.exceptionType,
    required this.message,
    required this.stackTrace,
    this.severity = TracerSeverity.error,
    this.fatal = false,
    this.issueKey,
    this.customKeys = const <String, String>{},
    this.breadcrumbs = const <TracerBreadcrumb>[],
    this.library,
    this.context,
    this.error,
    DateTime? timestamp,
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc();

  /// Runtime type name of the Dart error, for example `FormatException`.
  ///
  /// Tracer groups events by stack trace, but this string is what makes the
  /// event readable in the events list, so it is always sent.
  final String exceptionType;

  /// The error message, that is `error.toString()` with the leading type name
  /// stripped when Dart duplicated it there.
  final String message;

  /// The parsed Dart stack trace. Its [DartStackTrace.raw] is always forwarded
  /// verbatim so an obfuscated trace stays decodable by `flutter symbolize`.
  final DartStackTrace stackTrace;

  /// How severe the error is. Note that [TracerSeverity.fatal] counts against
  /// the crash-free metric on Android and iOS.
  final TracerSeverity severity;

  /// Whether the error terminated (or should be treated as terminating) the
  /// current run of the application.
  ///
  /// A Dart error never kills the process, so this is always a judgement call
  /// made by the caller rather than an observed fact.
  final bool fatal;

  /// Optional Tracer `issueKey`, which overrides stack-trace-based grouping.
  final String? issueKey;

  /// Custom key/value pairs attached to this single event.
  final Map<String, String> customKeys;

  /// The breadcrumb trail captured before the error.
  final List<TracerBreadcrumb> breadcrumbs;

  /// `FlutterErrorDetails.library`, when the event came from Flutter itself.
  final String? library;

  /// A description of `FlutterErrorDetails.context`, when available.
  final String? context;

  /// The original Dart error object.
  ///
  /// Available only inside [TracerOptions.beforeSend]; it is never serialized
  /// and never leaves the Dart isolate.
  final Object? error;

  /// When the error happened, always in UTC.
  final DateTime timestamp;

  /// The single-line title shown in the Tracer events list.
  String get title =>
      message.isEmpty ? exceptionType : '$exceptionType: $message';

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing `null` keeps the current value; use the dedicated `remove*` flags
  /// where a field genuinely needs to be cleared.
  TracerEvent copyWith({
    String? exceptionType,
    String? message,
    DartStackTrace? stackTrace,
    TracerSeverity? severity,
    bool? fatal,
    String? issueKey,
    Map<String, String>? customKeys,
    List<TracerBreadcrumb>? breadcrumbs,
    String? library,
    String? context,
    Object? error,
    DateTime? timestamp,
    bool removeIssueKey = false,
    bool removeBreadcrumbs = false,
  }) {
    return TracerEvent(
      exceptionType: exceptionType ?? this.exceptionType,
      message: message ?? this.message,
      stackTrace: stackTrace ?? this.stackTrace,
      severity: severity ?? this.severity,
      fatal: fatal ?? this.fatal,
      issueKey: removeIssueKey ? null : (issueKey ?? this.issueKey),
      customKeys: customKeys ?? this.customKeys,
      breadcrumbs: removeBreadcrumbs
          ? const <TracerBreadcrumb>[]
          : (breadcrumbs ?? this.breadcrumbs),
      library: library ?? this.library,
      context: context ?? this.context,
      error: error ?? this.error,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Serializes the event for the method channel and the HTTP transport.
  ///
  /// [error] is deliberately omitted: an arbitrary Dart object cannot cross a
  /// platform channel, and sending its `toString()` twice would only duplicate
  /// [message].
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'exceptionType': exceptionType,
      'message': message,
      'severity': severity.wireName,
      'fatal': fatal,
      'timestamp': timestamp.toIso8601String(),
      if (issueKey != null) 'issueKey': issueKey,
      if (library != null) 'library': library,
      if (context != null) 'context': context,
      if (customKeys.isNotEmpty) 'customKeys': customKeys,
      'stackTrace': stackTrace.toMap(),
      if (breadcrumbs.isNotEmpty)
        'breadcrumbs':
            breadcrumbs.map((TracerBreadcrumb b) => b.toMap()).toList(),
    };
  }

  @override
  String toString() => 'TracerEvent($title)';
}
