# apptracer_flutter_http

A pure-Dart transport to the HTTP ingest of [Tracer](https://apptracer.ru), for
[`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter),
the unofficial Flutter integration.

> Not affiliated with, endorsed by, or supported by VK or OK.TECH.

Русская версия: [README.md](README.md).

It posts `POST /api/crash/uploadBatch`, authenticating with the same `appToken`
the Android plugin uses. The wire format was recovered by capturing a live
request from the vendor's JS SDK and is written down in
[web-protocol.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md).

> This package used to be called `apptracer_flutter_sentry` and spoke the Sentry
> protocol, on the belief that Tracer ingests that way everywhere. For web that
> was wrong: Tracer has its own JavaScript SDK, an ordinary JS project is issued
> no DSN, and events go to Tracer's own ingest. Sentry ingest does exist — for
> platforms with no Tracer SDK, with a DSN issued when the project is created
> through VK Cloud — and it stayed a package of its own,
> [`apptracer_flutter_sentry`](https://github.com/KonstantenKomkov/apptracer_flutter/tree/main/packages/apptracer_flutter_sentry).
> Split 2026-08-26, before the first release.

On **web** it is used automatically by `apptracer_flutter_web`. On **desktop and
Aurora OS** register it yourself:

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';

void main() {
  TracerPlatform.instance = TracerHttpTracer(
    facts: PlatformClientFacts(),
    sdkVersion: '0.1.0',
  );
  Tracer.initialize(
    options: const TracerOptions(appToken: 'appToken from the project settings'),
    appRunner: () => runApp(const MyApp()),
  );
}
```

## Scope

Dart errors only. Native crashes, ANRs and hangs need a native SDK: on Android
and iOS the native implementations remain the right choice, and on Aurora OS the
vendor offers a C/C++ library with system minidumps that Dart cannot reach. On
desktop and Aurora this package covers its half, and does not replace a native
SDK.

## Status

The format was accepted by the live server on 2026-08-26: an event built to this
shape came back `200 {"success":true}` and appeared in the project's console.
What remains unknown is listed in
[web-protocol.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md).
