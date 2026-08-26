import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';

/// Splits an arbitrary Dart error into the type name and message that Tracer
/// displays.
///
/// Dart has no common base class for thrown values — `throw 'oops'` is legal —
/// so this has to work for any [Object].
class ErrorNormalizer {
  const ErrorNormalizer._();

  /// The type name Tracer shows as the event title, for example
  /// `FormatException` or `_TypeError`.
  static String typeOf(Object? error) {
    if (error == null) {
      return 'NullThrownError';
    }
    if (error is String) {
      // `throw 'some message'` carries no type information of its own.
      return 'String';
    }
    return error.runtimeType.toString();
  }

  /// The message Tracer shows next to the type name.
  ///
  /// Dart's convention is for `toString()` to start with the type name, which
  /// would otherwise be repeated in the title; that prefix is removed.
  static String messageOf(Object? error) {
    if (error == null) {
      return 'A null value was thrown';
    }
    final text = error.toString();
    final type = typeOf(error);
    if (text == type) {
      return '';
    }
    for (final separator in const <String>[': ', ' (']) {
      final prefix = '$type$separator';
      if (text.startsWith(prefix)) {
        return separator == ' ('
            ? text.substring(type.length).trim()
            : text.substring(prefix.length);
      }
    }
    return text;
  }

  /// Builds a [TracerEvent] from a raw error and stack trace.
  static TracerEvent fromError(
    Object? error,
    Object? stackTrace, {
    required TracerSeverity severity,
    required bool fatal,
    String? issueKey,
    Map<String, String> customKeys = const <String, String>{},
    List<TracerBreadcrumb> breadcrumbs = const <TracerBreadcrumb>[],
  }) {
    return TracerEvent(
      exceptionType: typeOf(error),
      message: messageOf(error),
      stackTrace: DartStackTrace.parse(stackTrace),
      severity: severity,
      fatal: fatal,
      issueKey: issueKey,
      customKeys: customKeys,
      breadcrumbs: breadcrumbs,
      error: error,
    );
  }

  /// Builds a [TracerEvent] from [FlutterErrorDetails].
  ///
  /// `FlutterErrorDetails` carries context the plain error does not: which
  /// library raised it and what the framework was doing at the time. Both are
  /// preserved, because they are usually what makes a framework error
  /// diagnosable.
  static TracerEvent fromFlutterError(
    FlutterErrorDetails details, {
    required TracerSeverity severity,
    required bool fatal,
    Map<String, String> customKeys = const <String, String>{},
    List<TracerBreadcrumb> breadcrumbs = const <TracerBreadcrumb>[],
  }) {
    final context = details.context;
    return TracerEvent(
      exceptionType: typeOf(details.exception),
      message: messageOf(details.exception),
      stackTrace: DartStackTrace.parse(details.stack),
      severity: severity,
      fatal: fatal,
      library: details.library,
      context: context?.toDescription(),
      customKeys: customKeys,
      breadcrumbs: breadcrumbs,
      error: details.exception,
    );
  }
}
