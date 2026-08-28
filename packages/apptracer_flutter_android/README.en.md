# apptracer_flutter_android

The Android implementation of [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter), an unofficial
Flutter integration with [Tracer](https://apptracer.ru).

> Not affiliated with, endorsed by, or supported by VK or OK.TECH.

Русская версия: [README.md](README.md).

You do not need to depend on this package directly; `apptracer_flutter` pulls
it in.

## What it does

Forwards Dart errors to `ru.ok.tracer:tracer-crash-report`. Native crashes,
ANRs and the crash-free metric are handled by that SDK on its own — this plugin
only supplies the half the SDK cannot see.

A Dart error is wrapped in a synthetic `Throwable` whose `stackTrace` is built
from the Dart frames. Reporting the JVM stack instead would give every Dart
error in the application the same frames and collapse them all into one Tracer
issue.

## Setup

The Tracer SDK is a `compileOnly` dependency here, so the host application adds
it — along with the `ru.ok.tracer` Gradle plugin, which is where `appToken`
comes from. See the [README](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/packages/apptracer_flutter/README.en.md#android).

The one piece of SDK configuration this package needs, it applies itself, with
no line of manifest: the non-fatal rate limit (10 per hour instead of a hard 8
per session — and every Dart error here is a non-fatal). It is installed by
`TracerAutoConfigProvider`, which the system creates ahead of Tracer's own
provider. An `Application` implementing `HasTracerConfiguration` cancels it,
which is what `TracerApplication` is for: subclass it. Why it works this way,
and where it is fragile, is documented on `TracerAutoConfig`.

Two things this plugin will tell you about at runtime, rather than failing
silently:

* the Tracer SDK missing from the runtime classpath;
* the `ru.ok.tracer` Gradle plugin not applied, detected by the absence of the
  generated `tracer_app_token` resource.

Requires `minSdk 21`, matching `ru.ok.tracer:tracer-commons`.
