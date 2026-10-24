import 'dart:io';

/// Selects only the current platform's ingest configuration.
String get probeDsn => Platform.isWindows
    ? Platform.environment['TRACER_WINDOWS_SENTRY_DSN'] ??
        const String.fromEnvironment('TRACER_WINDOWS_SENTRY_DSN')
    : Platform.isLinux
        ? Platform.environment['TRACER_LINUX_SENTRY_DSN'] ??
            const String.fromEnvironment('TRACER_LINUX_SENTRY_DSN')
        : Platform.environment['TRACER_MACOS_SENTRY_DSN'] ??
            const String.fromEnvironment('TRACER_MACOS_SENTRY_DSN');
