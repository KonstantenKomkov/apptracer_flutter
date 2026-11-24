# Release and migration history

Current versions and limitations belong to [platform-matrix.md](platform-matrix.md).
This file preserves release-specific notes instead of mixing them into the quick
start. Dated acceptance documents are historical evidence, not promises for newer code.

## Migrating the facade from 1.x to 2.0

Facade 2.0.0 removes five deprecated exports from
`package:apptracer_flutter/apptracer_flutter.dart`. If your application creates
a `TracerClient`, move startup to the application's entry point:

```dart
await Tracer.initialize(options: options, appRunner: () => runApp(const MyApp()));
```

For consent-driven collection, initialize once with
`TracerNativeInitialization.deferred`, then call `Tracer.startCollection(options)`
after consent and `Tracer.stopAndClearCollection()` on revocation. Keep the
application's `TracerOptions` if you need to change them for a later session.
Replace calls on your client with `Tracer.recordError`, `Tracer.setCustomKey`,
`Tracer.log` and the corresponding static methods. The facade owns one client
per isolate.

`Tracer.initialize` installs the configured error handlers. Use
`Tracer.recordFlutterError` to forward framework errors manually and
`TracerOptions.beforeSend` to inspect or transform the resulting `TracerEvent`.
The facade handles deduplication and buffers breadcrumbs added through
`Tracer.addBreadcrumb`. This covers the reporting flow previously exposed
through `ErrorHandlerChain`, `ErrorHandlerBindings`, `ErrorNormalizer`,
`EventDeduplicator` and `BreadcrumbBuffer`.

Tests that assigned `Tracer.client` can register a fake `TracerPlatform.instance`
before initialization, observe events on the fake, then stop collection and
restore the previous platform in teardown.

## apptracer_flutter 1.5.0 and desktop 2.0.0

The facade and adapters use a common delivery listener. On desktop, upgrade
the facade and adapter together. macOS uses Swift Package Manager, and the
desktop package requires Flutter 3.44 / Dart 3.12 or later.
[Release versions and archive hashes](publishing.md#coordinated-desktop-200-release).

## apptracer_flutter 1.4.0

Use `copyWith(removeLibrary: true, removeContext: true)` in `beforeSend` to
clear Flutter metadata. Events and breadcrumbs snapshot their collections.
Applications that use the implementation types exported by the facade should
migrate to `Tracer` before 2.0.0.
[Published packages](publishing.md#flutter-140-release-2026-11-22).

## apptracer_flutter 1.3.0

Android adapter 0.4.2 restores per-event context on the native SDK. Android
and iOS use the typed Pigeon bridge with a fallback for older adapters. Web
retries eligible queued reports across reconnects and browser restarts.
[Published versions](publishing.md#flutter-130-release-2026-11-22).

## apptracer_flutter 1.2.0 runtime APIs

`Tracer.pauseCollection()` / `resumeCollection()` pauses and resumes an existing
authorized Android SDK 1.6.1 session while retaining data and in-flight uploads.
Logout requires `stopAndClearCollection`; a new authorized `startCollection`
recreates collection after successful deferred cleanup. iOS 1.5.2 still returns
`restartRequired`.

`runHeapDump(tag: ...)`, `runDiskUsage()` and `setHeapDumpEnabled(bool)` require
explicit host installation of optional modules and heap provider setup before
SDK startup. Managed deferred cleanup does not cover these modules. `invoked`
means that the native method returned, not that a sample was delivered.
These APIs require `apptracer_flutter_android ^0.4.0` and
`apptracer_flutter_platform_interface ^0.2.1`.

See [release-1.2.0.md](release-1.2.0.md) and
[task-23-collection-lifecycle.md](task-23-collection-lifecycle.md).

## Android SDK 1.6.2 migration

Use `apptracer_flutter ^1.2.1` (Android adapter `^0.4.1`) and follow the current
[Android setup guide](android-guide.en.md). Hosts on 1.4.0, 1.5.2 and 1.6.1 retain
previous lifecycle behavior.

- `startCollection` resumes an initialized SDK 1.6.1 or 1.6.2 after native
  `Tracer.disable()`. Deferred full cleanup on those versions permits a fresh
  authorized session; SDK 1.4.0/1.5.2 and automatic initialization still require
  a new process.
- With `uploadMapping=false`, SDK 1.6.1 generates a zero `buildUuid`; service-side
  JVM recovery is not promised in that mode.
- Known Tracer defect: a tested Kotlin crash restores class/method but displays
  `.java:14` instead of `.kt:6`. Keep the exact `mapping.txt` and raw stack for
  local R8 Retrace. It remains an external defect, not a fixed package behavior.
- Full Flutter `assembleRelease` cannot store configuration cache on the audited
  Flutter 3.47.4 / AGP 8.9.1 / Gradle 8.12 / JDK 21 toolchain. Use
  `--no-configuration-cache` or `org.gradle.configuration-cache=false`.
- Optional heap/disk modules can pause the VM/UI and lose offline samples; their
  WorkManager lifecycle is outside supported deferred cleanup.

[Historical SDK 1.6.1 acceptance](android-sdk-1.6.1-acceptance.md) and
[diagnostic limitations](android-sdk-1.6.1-diagnostics.md) describe only the
listed build and environment.
