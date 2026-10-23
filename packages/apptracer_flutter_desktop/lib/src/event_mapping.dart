import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Converts only the already-filtered Tracer value, never its original error.
SentryEvent toSentryEvent(TracerEvent source) {
  final frames = source.stackTrace.frames
      .where((frame) => frame.isSymbolic || frame.needsSymbolication)
      .map((frame) => SentryStackFrame(
            absPath: frame.uri,
            fileName: frame.fileName,
            function: frame.member,
            package: frame.packageName,
            lineNo: frame.line,
            colNo: frame.column,
            instructionAddr: frame.absoluteAddress == null
                ? null
                : '0x${frame.absoluteAddress}',
            symbol: frame.symbol,
            platform: frame.needsSymbolication ? 'native' : 'dart',
            inApp: frame.uri == null
                ? null
                : !frame.uri!.startsWith('dart:') &&
                    !frame.uri!.startsWith('package:flutter/'),
          ))
      .toList()
      .reversed
      .toList();
  return SentryEvent(
    timestamp: source.timestamp,
    platform: 'dart',
    level: source.fatal
        ? SentryLevel.fatal
        : SentryLevel.fromName(source.severity.wireName),
    exceptions: [
      SentryException(
        type: source.exceptionType,
        value: source.message,
        stackTrace: frames.isEmpty
            ? null
            : SentryStackTrace(
                frames: frames,
                // Required by the pinned SDK's native/Dart debug-image integration.
                // ignore: invalid_use_of_internal_member
                baseAddr: source.stackTrace.isolateDsoBase == null
                    ? null
                    : '0x${source.stackTrace.isolateDsoBase}',
                // ignore: invalid_use_of_internal_member
                buildId: source.stackTrace.buildId,
              ),
        // Tracer's fatal flag is a classification, not proof of process death
        // or whether a try/catch was present.
        mechanism: Mechanism(type: 'apptracer', data: {'fatal': source.fatal}),
      ),
    ],
    fingerprint: source.issueKey == null ? null : [source.issueKey!],
    tags: Map.of(source.customKeys),
    breadcrumbs: source.breadcrumbs
        .map((crumb) => Breadcrumb(
              message: crumb.message,
              category: crumb.category,
              level: SentryLevel.fromName(crumb.level.wireName),
              timestamp: crumb.timestamp,
              data: Map<String, dynamic>.of(crumb.data),
            ))
        .toList(),
    contexts: Contexts.fromJson({
      'apptracer': {
        'dart_stack_trace': source.stackTrace.raw,
        'fatal': source.fatal,
        if (source.issueKey != null) 'issueKey': source.issueKey,
        if (source.library != null) 'library': source.library,
        if (source.context != null) 'context': source.context,
      },
    }),
  );
}

/// Prevents native/global scope data from undoing the Tracer beforeSend filter.
SentryEvent restoreFilteredFields(SentryEvent event, TracerEvent source) {
  final filtered = toSentryEvent(source);
  event
    ..tags = filtered.tags
    ..breadcrumbs = filtered.breadcrumbs
    ..fingerprint = filtered.fingerprint;
  event.contexts['apptracer'] = filtered.contexts['apptracer'];
  return event;
}
