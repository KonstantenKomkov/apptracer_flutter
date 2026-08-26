/// Pure-Dart transport to Tracer's own HTTP ingest.
///
/// Used by `apptracer_flutter_web`, and registered by hand on desktop and
/// Aurora OS, where the vendor offers no SDK a Flutter application can reach:
/// none at all for desktop, and a C/C++ library plus system minidumps for
/// Aurora.
///
/// This package used to speak the Sentry protocol, on the belief that Tracer
/// ingests over it everywhere. Measured on 2026-08-26, that belief was wrong on
/// every platform: no project hands out a DSN, and the vendor's own SDKs post
/// to `/api/crash/uploadBatch` authenticated by the project's `appToken`. The
/// wire format used here was recovered from a captured request and is written
/// down in `docs/web-protocol.md`.
///
/// What it cannot do is the other half of crash reporting: a native crash, an
/// ANR, or an Aurora minidump. Those need the vendor's native SDK, and on
/// desktop and Aurora this package covers Dart errors only.
library;

export 'src/platform_client_facts.dart';
export 'src/tracer_batch_item.dart';
export 'src/tracer_client_facts.dart';
export 'src/tracer_http_tracer.dart';
