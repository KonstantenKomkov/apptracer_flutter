/// Pure-Dart Sentry-protocol transport for `apptracer_flutter`.
///
/// This archived manual transport is available to existing Git consumers.
/// On supported desktops use the optional `apptracer_flutter_desktop` adapter
/// with the official Sentry SDK and the target project's DSN. Web uses
/// `apptracer_flutter_web` with the JS project's `appToken`. Aurora OS is
/// unsupported. See the [platform matrix](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md#summary).
library;

export 'src/sentry_dsn.dart';
export 'src/sentry_event_builder.dart';
export 'src/sentry_protocol_tracer.dart';
