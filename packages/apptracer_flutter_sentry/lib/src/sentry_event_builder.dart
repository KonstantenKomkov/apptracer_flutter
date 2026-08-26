import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';

/// Builds the Sentry event body Tracer's ingest expects.
///
/// Two details are Tracer's rather than Sentry's, and both are documented by
/// the vendor:
///
/// * `release` is taken verbatim, but Tracer strips everything up to and
///   including the last `@` — so `my_app@1.2.3` is stored as `1.2.3`. The same
///   value has to be used when uploading source maps, or nothing lines up.
/// * source maps are matched **by file path**, not by Debug ID as Sentry does.
///   Nothing here can fix a mismatch; it is the upload that has to agree with
///   the frames.
Map<String, Object?> buildSentryEvent({
  required TracerEvent event,
  required String eventId,
  String? release,
  String? environment,
}) {
  return <String, Object?>{
    'event_id': eventId,
    'timestamp': event.timestamp.toUtc().toIso8601String(),
    // `other` rather than `dart`: Sentry's own list has no Dart, and a platform
    // it does not know makes the ingest fall back to generic handling, which is
    // exactly what we want for frames it cannot classify.
    'platform': 'other',
    'level': _level(event.severity, fatal: event.fatal),
    if (release != null && release.isNotEmpty) 'release': release,
    if (environment != null && environment.isNotEmpty)
      'environment': environment,
    'exception': <String, Object?>{
      'values': <Map<String, Object?>>[
        <String, Object?>{
          'type': event.exceptionType,
          'value': event.message,
          'stacktrace': <String, Object?>{
            // Sentry renders frames oldest first and puts the throw site last,
            // which is the opposite of how Dart prints them.
            'frames': event.stackTrace.frames.reversed
                .map(_frame)
                .toList(growable: false),
          },
        },
      ],
    },
    if (event.breadcrumbs.isNotEmpty)
      'breadcrumbs': <String, Object?>{
        'values': event.breadcrumbs.map(_breadcrumb).toList(growable: false),
      },
    if (event.customKeys.isNotEmpty) 'tags': event.customKeys,
    'extra': <String, Object?>{
      // The one artefact that makes an obfuscated build decodable. Sentry has
      // nowhere better to put it, and `extra` is shown in Tracer under
      // «Данные» → «Context».
      'dart.stack_trace': event.stackTrace.raw,
      if (event.stackTrace.isObfuscated) 'dart.obfuscated': 'true',
      if (event.stackTrace.buildId != null)
        'dart.build_id': event.stackTrace.buildId,
    },
    // Grouping: an explicit key wins, exactly as it does on the native
    // platforms. Without one, Sentry groups on the frames itself.
    if (event.issueKey != null) 'fingerprint': <String>[event.issueKey!],
  };
}

Map<String, Object?> _frame(DartStackFrame frame) {
  final String? member = frame.member;
  return <String, Object?>{
    if (member != null) 'function': member,
    if (frame.uri != null) 'filename': frame.uri,
    if (frame.line != null) 'lineno': frame.line,
    if (frame.column != null) 'colno': frame.column,
    // Frames from the application are worth more than framework ones, and
    // Sentry uses this to decide what to show first.
    'in_app': frame.uri?.startsWith('package:flutter/') == false &&
        frame.uri?.startsWith('dart:') == false,
    if (frame.virtualAddress != null)
      'instruction_addr': '0x${frame.virtualAddress}',
  };
}

Map<String, Object?> _breadcrumb(TracerBreadcrumb crumb) => <String, Object?>{
      'timestamp': crumb.timestamp.toUtc().toIso8601String(),
      'message': crumb.message,
      if (crumb.category != null) 'category': crumb.category,
      'level': _level(crumb.level, fatal: false),
      if (crumb.data.isNotEmpty) 'data': crumb.data,
    };

String _level(TracerSeverity severity, {required bool fatal}) {
  if (fatal) {
    return 'fatal';
  }
  switch (severity) {
    case TracerSeverity.fatal:
      return 'fatal';
    case TracerSeverity.error:
      return 'error';
    case TracerSeverity.warning:
      return 'warning';
    case TracerSeverity.notice:
    case TracerSeverity.info:
      return 'info';
    case TracerSeverity.debug:
      return 'debug';
  }
}
