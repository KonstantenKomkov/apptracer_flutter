# apptracer_flutter_sentry

A pure-Dart Sentry-protocol transport for
[`apptracer_flutter`](https://github.com/komkovkonstantin/apptracer_flutter),
the unofficial Flutter integration with [Tracer](https://apptracer.ru).

> Not affiliated with, endorsed by, or supported by VK or OK.TECH.

Русская версия: [README.md](README.md).

Tracer ingests events over the Sentry protocol on platforms where it has no SDK
of its own — that is the vendor's documented recommendation. The Sentry DSN is
issued under **Settings → Project → API**, but only for a project created
through **VK Cloud**.

For Flutter that means desktop, and Aurora OS, where the vendor's C/C++ SDK with
system minidumps cannot be reached from Dart.

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_sentry/apptracer_flutter_sentry.dart';

void main() {
  TracerPlatform.instance = SentryProtocolTracer();
  Tracer.initialize(
    options: const TracerOptions(dsn: 'https://<key>@<host>/<project>'),
    appRunner: () => runApp(const MyApp()),
  );
}
```

## What it does not do

**Web does not use it.** Tracer has its own JavaScript SDK there, an ordinary JS
project is issued no DSN, and `apptracer_flutter_web` speaks the same HTTP
ingest that SDK speaks.

**No native crashes.** Crashes, ANRs and hangs need a native SDK: the native
implementations on Android and iOS, the vendor's C/C++ SDK on Aurora. This is
Dart errors only.

## Two things that are Tracer's, not Sentry's

**The version.** A Sentry SDK sends it as `release`. Tracer strips everything up
to and including the last `@`, so `my_app@1.2.3` is stored as `1.2.3` — and that
is the value a source-map upload has to use.

**Source maps are matched by file path**, not by Debug ID as Sentry does. When
the paths disagree, symbolication simply does not apply, silently.

## Status

Envelope and event construction are unit-tested and follow the documented Sentry
ingest format, but this transport has **not** been verified against a live
Tracer project: that needs one created through VK Cloud. See
[status.md](https://github.com/komkovkonstantin/apptracer_flutter/blob/main/docs/status.md).
