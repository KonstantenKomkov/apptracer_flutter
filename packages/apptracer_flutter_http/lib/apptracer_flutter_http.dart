/// Pure-Dart transport to Tracer's own HTTP ingest.
///
/// The Web adapter uses this transport automatically. It posts Dart errors to
/// `/api/crash/uploadBatch` with the JS project's `appToken`. The wire format
/// was recovered from a captured request on 2026-08-26 (see `docs/web-protocol.md`).
///
/// Manual registration is available for custom integrations. On supported
/// desktop configurations, add the optional stable `apptracer_flutter_desktop`
/// adapter, which uses the official Sentry SDK with the target project's DSN.
/// Aurora OS is unsupported. See the [platform matrix](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md#summary).
library;

export 'src/platform_client_facts.dart';
export 'src/tracer_batch_item.dart';
export 'src/tracer_client_facts.dart';
export 'src/tracer_delivery.dart';
export 'src/tracer_http_tracer.dart';
