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

The current checkout compiles against **1.6.1**. Use the matching 1.6.1 BOM
and Gradle plugin with `mavenCentral()` in plugin and dependency repositories;
keep `google()` for Android dependencies. No VK repository is required for
1.6.1. Hosts pinned to the previously audited 1.4.0/1.5.2 remain accepted;
retain their vendor repository configuration if their artifacts need it.
The old versions have no runtime `enable()` API. Full stop/clear still requires
a process restart. See the [1.6.1 audit and acceptance limits](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/android-sdk-1.6.1.md).

The one piece of SDK configuration this package needs, it applies itself, with
no line of manifest: the non-fatal rate limit (10 per hour instead of a hard 8
per session — and every Dart error here is a non-fatal). It is installed by
`TracerAutoConfigProvider`, which the system creates ahead of Tracer's own
provider. An `Application` implementing `HasTracerConfiguration` cancels it,
which is what `TracerApplication` is for: subclass it. Why it works this way,
and where it is fragile, is documented on `TracerAutoConfig`.

Four things this plugin will tell you about at runtime, rather than failing
silently. The first two also disable it:

* the Tracer SDK missing from the runtime classpath;
* the `ru.ok.tracer` Gradle plugin not applied, detected by the absence of the
  generated `tracer_app_token` resource;
* a `TracerOptions.appToken` that was passed — it is ignored on Android;
* a `TracerOptions.environment` that was passed — also ignored, the value comes
  from the Gradle plugin.

Requires `minSdk 21`, matching `ru.ok.tracer:tracer-commons`.


## Android tombstones (SDK 1.5.2)

Experimental system native crash reports are **off by default**. To enable
them without a custom `Application`, add this inside `<application>` in
`android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="ru.apptracer.flutter.experimentalTombstoneEnabled"
    android:value="true" />
```

Requires Tracer Android **1.5.2** and **Android 12 / API 31+**. The feature is
part of `tracer-crash-report`; `tracer-crash-report-native` is optional and
remains useful for native crashes on older Android versions. System libraries
can be symbolicated from tombstones; this does not guarantee Dart AOT
symbolication. Reports are recovered on a later SDK start.

An `Application` implementing `HasTracerConfiguration` replaces these defaults.
In its existing `CrashReportConfiguration.Builder`, call
`setExperimentalTombstoneEnabled(true)` and retain the non-fatal rate limit if
needed. A subclass of `TracerApplication` inherits the manifest setting.

This setting applies to automatic and deferred startup. It is configured on
Android before SDK initialization, not through `TracerOptions` in Dart.
Deferred collection still requires the manifest provider removal and explicit
`startCollection`; enabling the feature does not start collection by itself.
Perform a clean build after updating. The vendor Nexus configuration applies
to legacy SDK hosts; 1.6.1 uses Maven Central as described above.
