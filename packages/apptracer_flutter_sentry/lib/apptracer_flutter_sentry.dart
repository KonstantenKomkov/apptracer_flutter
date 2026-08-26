/// Pure-Dart Sentry-protocol transport for `apptracer_flutter`.
///
/// Tracer accepts events over the Sentry protocol on platforms where it has no
/// SDK of its own, and issues a Sentry DSN for a project created through VK
/// Cloud. For a Flutter application that is desktop, and Aurora OS when the
/// vendor's C/C++ SDK cannot be reached from Dart.
///
/// On **web** use `apptracer_flutter_web` instead: Tracer has a JavaScript SDK
/// there, an ordinary JS project is issued no DSN, and the web package speaks
/// the same HTTP ingest that SDK speaks. The alternative on desktop is
/// `apptracer_flutter_http`, which speaks that ingest too — undocumented, but
/// needing no VK Cloud project. Both are in `docs/platform-matrix.md`.
library;

export 'src/sentry_dsn.dart';
export 'src/sentry_event_builder.dart';
export 'src/sentry_protocol_tracer.dart';
