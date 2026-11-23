/// Pure-Dart transport to Tracer's own HTTP ingest.
///
/// Used automatically by `apptracer_flutter_web`. Manual registration remains
/// available for custom transports, but supported desktop applications should use
/// the optional `apptracer_flutter_desktop` adapter and the official Sentry SDK
/// with the target project's DSN. Aurora has no verified default HTTP integration.
///
/// This package used to speak the Sentry protocol, on the belief that Tracer
/// ingests over it everywhere. Measured on 2026-08-26, that belief was wrong for
/// web: an ordinary JS project hands out no DSN, and the vendor's SDK posts to
/// `/api/crash/uploadBatch` authenticated by the project's `appToken`. Desktop
/// Sentry projects do use a DSN. The HTTP wire format was recovered from a captured
/// request and is written down in `docs/web-protocol.md`.
///
/// What it cannot do is the other half of crash reporting: a native crash, an
/// ANR, or an Aurora minidump. Those need the vendor's native SDK, and on
/// desktop and Aurora this package covers Dart errors only.
library;

export 'src/platform_client_facts.dart';
export 'src/tracer_batch_item.dart';
export 'src/tracer_client_facts.dart';
export 'src/tracer_delivery.dart';
export 'src/tracer_http_tracer.dart';
