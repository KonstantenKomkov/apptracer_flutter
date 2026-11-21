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
comes from. See the [Android setup guide](../../docs/android-guide.en.md).

Adapter **0.4.1** compiles against SDK **1.6.2**, which fixes uploads on Android
API 23 and below. Add the [Tracer Maven repository](https://nexus-external.vkteam.ru/repository/maven-tracer-public-exposed/)
to both plugin and dependency resolution in the host, and pin the BOM and
Gradle plugin to 1.6.2. Keep Google Maven and Maven Central for other dependencies.

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

Requires Tracer Android **1.5.2, 1.6.1 or 1.6.2** and **Android 12 / API 31+**. The feature is
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
Perform a clean build after updating.

### Upgrading to Android SDK 1.6.2

Use `apptracer_flutter ^1.2.1` (Android adapter `^0.4.1`). Update the Android
repository settings, BOM and plugin as shown above, then rebuild the app. Hosts
pinned to 1.4.0, 1.5.2 or 1.6.1 retain their existing lifecycle behavior.

- `startCollection` can resume an initialized SDK 1.6.1 or 1.6.2 after native
  `Tracer.disable()`. `apptracer_flutter_android` 0.4.1 also recreates a fresh
  session after successful full deferred cleanup on SDK 1.6.1/1.6.2. SDK 1.4.0/1.5.2
  and automatic initialization still require a new process after full stop.
  Build-time disable requires a build configuration change.
  Observing state never implicitly resumes collection.
- The Gradle DSL flags are `uploadMapping` and `uploadNativeSymbols`. With both
  `false`, only `appToken` is required; either upload requires `pluginToken`.
  With `uploadMapping=false`, SDK 1.6.1 generates a zero `buildUuid`; service-side
  JVM stack recovery is not promised in this mode.
- **Known Tracer defect:** the tested Kotlin crash restores class/method but
  displays `.java:14` instead of `.kt:6`. Delivery and Java source recovery
  passed. Retain the full exact-build `mapping.txt` and raw obfuscated stack
  for local R8 Retrace. This release accepts the limitation; it does not fix it.
- Full Flutter `assembleRelease` cannot store configuration cache on the
  audited Flutter 3.47.4 / AGP 8.9.1 / Gradle 8.12 / JDK 21 toolchain, including
  without Tracer. Use Gradle `--no-configuration-cache` or set
  `org.gradle.configuration-cache=false` in `gradle.properties`.
- `HeapDumps.runNow`, `DiskUsage.runNow` and lazy `provideEnabled` belong to
  optional native modules. `apptracer_flutter` 1.2.0 exposes them through
  Dart; the application must install the modules explicitly. Heap dumps can pause the VM/UI even when called from a background
  thread; offline samples can be deleted without retry. Their WorkManager
  lifecycle is outside the supported deferred cleanup contract.
- Enabling both the native module and experimental tombstones can produce a
  MINIDUMP and a TOMBSTONE for one crash. The example opts into tombstones separately.

SDK 1.6.1 acceptance used a release/R8 arm64 Android 15 / API 35 emulator. It does not
certify physical devices or native/Dart symbolication.
[Acceptance](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/android-sdk-1.6.1-acceptance.md),
[diagnostic module limits](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/android-sdk-1.6.1-diagnostics.md).

## Runtime APIs in apptracer_flutter 1.2.0

`apptracer_flutter` 1.2.0 provides `Tracer.pauseCollection()` / `resumeCollection()` for
an existing authorized Android SDK 1.6.1 session. Pause retains data and does
not cancel uploads. Logout still requires `stopAndClearCollection`; restarting
after successful cleanup recreates collection on Android 1.6.1 in deferred
mode. iOS 1.5.2 still returns `restartRequired`.

`runHeapDump(tag: ...)`, `runDiskUsage()` and `setHeapDumpEnabled(bool)` require
explicit host installation of the optional modules; the heap provider must also
be installed before SDK startup. Managed deferred cleanup does not cover these
modules. `invoked` means the native method returned, not successful delivery.
These APIs require `apptracer_flutter_android ^0.4.0` and
`apptracer_flutter_platform_interface ^0.2.1`; `apptracer_flutter` declares
these dependencies automatically.
[Release status and publication order](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/release-1.2.0.md).
[API coverage, setup, verification and accepted task 23 limits](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/task-23-collection-lifecycle.md).
