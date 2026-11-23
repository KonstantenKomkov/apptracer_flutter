# apptracer_flutter_web

The web implementation of [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter), an unofficial Flutter
integration with [Tracer](https://apptracer.ru).

> Not affiliated with, endorsed by, or supported by VK or OK.TECH.

Русская версия: [README.md](README.md).

You do not need to depend on this package directly; `apptracer_flutter` pulls
it in.

## Why it does not wrap the Tracer JS SDK

Tracer's JavaScript SDK ships as the npm package `@apptracer/sdk`, and a Flutter
web build has no way to bundle an npm package. So this implementation speaks the
same ingest that SDK speaks — `POST /api/crash/uploadBatch`, authenticated by
the project's `appToken` — from pure Dart, through
[`apptracer_flutter_http`](https://github.com/KonstantenKomkov/apptracer_flutter/tree/main/packages/apptracer_flutter_http).

Before 2026-08-26 this implementation sent Sentry envelopes. Verification on
that date showed that ordinary JS projects receive an `appToken` and the
vendor's JavaScript SDK uses Tracer's HTTP ingest. The captured request is in
[web-protocol.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md).

Consequences:

* Pass the **JS project's** token in `TracerOptions.webAppToken` or the shared
  `appToken` field. The Web adapter ignores `dsn`.
* Only Dart errors are captured. A failure inside an unrelated third-party
  `<script>` is invisible.
* Frames are `dart2js` frames, and Tracer matches source maps **by file path,
  not by Debug ID**. See [symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md).
* There is no such thing as a native crash on web, and no crash-free metric:
  the vendor SDK's `trackSession` is not sent.
* The ingest requires a `deviceId`, so the implementation creates one: a UUID in
  `localStorage` under `apptracer_flutter.deviceId`, surviving a reload. In a
  private window, or with site data blocked, it lives as long as the tab. It is
  the only identifier this package invents.
