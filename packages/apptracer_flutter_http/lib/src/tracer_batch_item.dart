import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';

import 'tracer_client_facts.dart';

/// Builds one item of the `/api/crash/uploadBatch` array.
///
/// The shape is not documented by the vendor. It was recovered on 2026-08-26 by
/// running `@apptracer/sdk` 2.6.9 in a browser with its `apiHost` pointed at a
/// local server that printed what arrived; the captured request is quoted in
/// `docs/web-protocol.md`. The fields that request did not happen to exercise —
/// `logsFile`, `tags`, `userId` — were read on 2026-08-27 out of the SDK's own
/// bundle, `lib/main/index.mjs`, in `StackTraceUploader`. Anything here that
/// looks arbitrary is arbitrary because the wire format is.
Map<String, Object?> buildBatchItem({
  required TracerEvent event,
  required TracerClientFacts facts,
  required String versionName,
  required int versionCode,
  required String environment,
  required String sdkVersion,
  Map<String, String> customKeys = const <String, String>{},
  String? userId,
  String? logsFile,
}) {
  // Global keys first, the event's own on top — the same merge the vendor does
  // in `getErrorData`.
  final Map<String, String> keys = <String, String>{
    ...customKeys,
    ...event.customKeys.map(
      (String key, Object? value) => MapEntry<String, String>(key, '$value'),
    ),
  };
  // The vendor sends CRASH for anything that terminated the page and NON_FATAL
  // for everything reported by hand. A Dart error never terminates the page, so
  // only an explicitly fatal event earns CRASH.
  final String kind = event.fatal ? 'CRASH' : 'NON_FATAL';

  return <String, Object?>{
    'type': kind,
    'format': 'JS_STACKTRACE',
    'severity': kind,
    'uploadBean': <String, Object?>{
      'environment': environment,
      'deviceId': facts.deviceId,
      'sessionUuid': facts.sessionUuid,
      'versionName': versionName,
      'versionCode': versionCode,
      'properties': <String, Object?>{
        'timestamp': event.timestamp.millisecondsSinceEpoch,
        'date': event.timestamp.toIso8601String(),
        'host': facts.host,
        // The vendor distinguishes a hand-reported error from a caught one.
        // Ours are all reported through the same call, and `fatal` is the only
        // signal we have about which is which.
        'errorEventType': event.fatal ? 'error' : 'manual',
        'screenWidth': facts.screenWidth,
        'screenHeight': facts.screenHeight,
        'screenOrientationAngle': facts.screenOrientationAngle,
        'documentVisibilityState': facts.documentVisibilityState,
        'tracerSdkVersion': sdkVersion,
        // See the note on `tags` below: this is the copy the console renders.
        ...keys,
        if (userId != null) 'userId': userId,
        if (event.issueKey != null) 'issueKey': event.issueKey,
      },
      // Custom keys go out twice, and both times deliberately. The console's
      // «Данные» tab renders `properties` and ignores `tags` — measured
      // 2026-08-27 by sending one event each way and reading the tab — while
      // `tags`, one `key=value` string each, is what the vendor's own
      // `StackTraceUploader.getUploadBeanForError` builds out of its key
      // store. Sending only what renders would drop whatever the vendor uses
      // tags for; sending only what the vendor sends would leave the tab
      // empty.
      if (keys.isNotEmpty)
        'tags': <String>[
          for (final MapEntry<String, String> entry in keys.entries)
            '${entry.key}=${entry.value}',
        ],
    },
    // Base64 of the log buffer; absent when nothing was logged, as in the SDK.
    if (logsFile != null) 'logsFile': logsFile,
    // The vendor's SDK sends `Error: message` followed by indented `at` lines.
    // A Dart trace is close enough in shape that the same field carries it, and
    // it is the only place a reader will find the real frames.
    'stackTrace': _stackTraceText(event),
  };
}

String _stackTraceText(TracerEvent event) {
  final StringBuffer buffer = StringBuffer()
    ..write(event.exceptionType)
    ..write(': ')
    ..writeln(event.message);
  buffer.write(event.stackTrace.raw);
  return buffer.toString();
}
