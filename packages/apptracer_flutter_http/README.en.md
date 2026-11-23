# apptracer_flutter_http

A pure-Dart transport to the HTTP ingest of [Tracer](https://apptracer.ru), for
[`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter),
the unofficial Flutter integration.

> Not affiliated with, endorsed by, or supported by VK or OK.TECH.

Русская версия: [README.md](README.md).

On Web, `apptracer_flutter_web` uses this transport automatically. It sends Dart
errors to `POST /api/crash/uploadBatch` with the JS project's `appToken`. The
[wire format](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md)
was recovered from a request sent by the vendor's JavaScript SDK.

For supported desktop configurations, add the optional stable
`apptracer_flutter_desktop` adapter. It uses the official Sentry SDK with the
target Tracer project's DSN. Aurora OS is unsupported. See the
[platform matrix](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md#summary).

For a custom integration that needs manual HTTP delivery:

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';

void main() {
  TracerPlatform.instance = TracerHttpTracer(
    facts: PlatformClientFacts(),
    sdkVersion: '0.2.1',
  );
  Tracer.initialize(
    options: const TracerOptions(appToken: 'appToken from the project settings'),
    appRunner: () => runApp(const MyApp()),
  );
}
```

## Scope

The HTTP transport reports Dart errors only. Native crashes, ANRs and hangs require a native SDK.

On 2026-08-26, before the first release, the manual Sentry protocol implementation
was split into the now archived [apptracer_flutter_sentry](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/packages/apptracer_flutter_sentry/README.en.md).

## Status

`startCollection` supports explicit opt-in after deferred bootstrap.
`stopAndClearCollection` immediately disables collection, clears logs, custom keys
and user ID, and deletes the queue. Successful cleanup returns `disabled`; a failure
returns `error`. The default in-memory queue holds up to 100 events or 1 MiB for
24 hours. Transient failures are retried up to five total attempts with a 10-second
request timeout.
A later start works in the same process and creates a fresh owned HTTP client;
diagnostics supplied while disabled are discarded. An already started request
may complete. An injected `httpClient` remains caller-owned and is not closed.

The format was accepted by the live server on 2026-08-26: an event built to this
shape came back `200 {"success":true}` and appeared in the project's console.
What remains unknown is listed in
[web-protocol.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md).
