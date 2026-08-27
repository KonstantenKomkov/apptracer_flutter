# apptracer_flutter_web

The web implementation of [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter), an unofficial Flutter
integration with [Tracer](https://apptracer.ru).

> Not affiliated with, endorsed by, or supported by VK or OK.TECH.

Русская версия: [README.md](README.md).

You do not need to depend on this package directly; `apptracer_flutter` pulls
it in.

## Why it does not wrap the Tracer JS SDK

Tracer's JavaScript SDK ships as the npm package `@apptracer/sdk`, and a Flutter
web build has no way to bundle an npm package. Tracer also ingests events over
the Sentry protocol on every platform, and that path needs nothing but an HTTP
client — so this implementation posts Sentry envelopes from pure Dart, through
[`apptracer_flutter_http`](https://github.com/KonstantenKomkov/apptracer_flutter/tree/main/packages/apptracer_flutter_http).

Consequences:

* Only Dart errors are captured. A failure inside an unrelated third-party
  `<script>` is invisible.
* Frames are `dart2js` frames, and Tracer matches source maps **by file path,
  not by Debug ID**. See [symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md).
* `TracerOptions.dsn` is required; `appToken` is not used by this path.
