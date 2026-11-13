# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below `1.0.0`, a breaking change bumps the minor version,
as pub.dev expects.

## [0.4.0] - 2026-11-13

### Added

- Implement explicit runtime pause/resume on Android SDK 1.6.1.
- Expose opt-in heap/disk commands with typed results and a synchronous native
  heap-enabled provider. No optional modules are installed automatically.

### Fixed

- Exclude test/build output and local development files from standalone
  publication archives.

- Recreate Android SDK 1.6.1 deferred sessions after successful full cleanup,
  with fresh executors, session/device identifiers, native writer and ANR
  watchdog. Repeated login to the same or a different account can collect again
  without restarting the application process.
- Drain old writers and purge old reports/context before a new session starts;
  stale engines and failed cleanup cannot silently reopen collection.

### Changed

- Require `apptracer_flutter_platform_interface ^0.2.1`.
- Validate session recreation in release/R8 builds, including offline purge,
  JVM/native/ANR recovery and public Dart heap/disk sample delivery.

### Known limitations

- Full cleanup with automatic initialization or SDK 1.4.0/1.5.2 still requires
  a new process. Build-time disable cannot be reversed at runtime.
- Optional diagnostic modules are outside managed deferred cleanup and require
  explicit host setup. `invoked` is not delivery confirmation. Heap dumps may
  pause the VM/UI; offline samples can be deleted without retry.
- The previously documented Kotlin file/line recovery defect and full Flutter
  configuration-cache limitation remain unchanged.

## [0.3.0] - 2026-11-13

### Added

- Resume an initialized SDK 1.6.1 runtime pause through `startCollection` and
  the version-checked native `Tracer.enable()` API. Build-time disable and full
  stop/clear remain terminal; full stop/clear requires a new process.

### Changed

- Compile and test against Tracer SDK 1.6.1 from Maven Central. The application
  still supplies the matching SDK BOM and Gradle plugin; 1.4.0/1.5.2 hosts
  remain accepted with their previous runtime limitations.
- Document separate mapping/native upload controls, optional diagnostic module
  behavior and release/R8 API 35 acceptance.

### Known limitations

- Tracer restores the tested Kotlin crash class/method but displays incorrect
  source file/line. Exact-build R8 Retrace restores the correct `.kt` location;
  retain the full mapping for local diagnosis. This external defect is accepted
  for this release, not fixed by it.
- Full Flutter assemble configuration cache fails on the audited toolchain,
  including without Tracer. Use `--no-configuration-cache`.
- Optional heap dumps can pause the VM/UI; offline diagnostic samples may be
  deleted without retry. These modules are not enabled by default.

## [0.2.1] - 2026-10-16

### Added

- Opt-in Android 12+ tombstones through application manifest metadata
  `ru.apptracer.flutter.experimentalTombstoneEnabled` or native configuration.
  The default remains off; `tracer-crash-report-native` is not required.

### Changed

- Compile and test against Tracer Android SDK 1.5.2 using the vendor Nexus
  repository; the SDK remains a host-supplied `compileOnly` dependency.
- Extend the version-checked deferred adapter to 1.5.2, retaining 1.4.0 support.
  Re-audit startup, revocation, diagnostic stores and native writer signatures;
  preserve the separate scope of earlier 1.4.0 device verification.

## [0.2.0] - 2026-10-03

### Added

- An opt-in deferred adapter pinned to Android Tracer 1.4.0, with controlled
  startup, revocable work admission, diagnostic cleanup, and shared process state.
  After active collection is stopped, re-consent requires a process restart.
  The host must remove both startup providers for deferred mode; automatic mode
  remains the default. Release/R8 verification covers offline and in-flight
  requests, account changes, cleanup failures, and native/JVM/ANR recovery.

### Changed

- Require platform interface `^0.2.0` for the collection lifecycle contract.

### Fixed

- Allow R8 release builds without the optional vendor SDK by tolerating its absent
  `javax.inject.Provider` type; absence still returns `sdk_missing` at runtime.

## [0.1.1] - 2026-08-30

### Changed

- The Kotlin Gradle Plugin is now applied only under AGP 8 and older, so an
  application no longer gets Flutter's "plugins that apply Kotlin Gradle Plugin
  (KGP)" warning because of this package. Under AGP 9 the Android plugin
  compiles Kotlin itself (Built-in Kotlin) and a library subproject applying KGP
  is what future Flutter releases will fail on. The plugin is applied through
  `pluginManager.apply` rather than `apply plugin:`, because flutter_tools reads
  the text of `android/build.gradle` and would otherwise keep reporting this
  package as unmigrated from a branch that never runs on AGP 9. The Kotlin JVM
  target is set through whichever DSL the toolchain offers, since
  `android.kotlinOptions` no longer exists under Built-in Kotlin.

  The minimum Flutter version is unchanged: the alternative — dropping KGP
  outright, as the migration guide suggests — works only from Flutter 3.44,
  which is where flutter_tools began applying KGP for plugins that declare none.

  Verified in an application on Flutter 3.44.9 with AGP 9.1.1, Kotlin 2.3.20 and
  `android.builtInKotlin=false`: this package is gone from the warning's list,
  the build succeeds, and the plugin's classes still come out at JVM target 1.8.
  Not verified under `android.builtInKotlin=true`, which no plugin can pass on
  Flutter 3.44.x: that version applies KGP to every plugin subproject that does
  not declare one, migrated or not.

## [0.1.0] - 2026-08-28

### Added

- `ru.apptracer.flutter.TracerApplication`, an `Application` that turns on the
  non-fatal rate limit. Every Dart error this package reports is a non-fatal,
  and the SDK's hard default is 8 of them per session, so an application that
  writes no configuration of its own loses errors silently. Naming this class
  in the manifest replaces writing one by hand; it cannot be a package default,
  because the SDK reads configuration from the `Application` object and a
  plugin is not one. Built through `CrashReportConfiguration.Builder` rather
  than the SDK's inline `build {}`, which is compiled for JVM target 11 and
  would impose that on every consumer.

- Initial release.
- Forwards Dart errors to `ru.ok.tracer:tracer-crash-report` as a synthetic
  `Throwable` whose stack frames are the Dart frames, so Tracer groups by the
  Dart call site rather than by the identical JNI frames.
- Maps breadcrumbs onto `TracerCrashReport.log` and custom keys onto
  `Tracer.setCustomProperty`.
- Detects a missing Tracer SDK or a missing `ru.ok.tracer` Gradle plugin and
  reports "disabled" with an actionable message instead of crashing.
- The Tracer SDK is a `compileOnly` dependency: this package never pins a vendor
  SDK version into a host build and redistributes nothing.

### Changed

- The non-fatal rate limit is now applied by the package itself, so an
  integration no longer has to name `ru.apptracer.flutter.TracerApplication` in
  its manifest. `TracerAutoConfigProvider`, a `ContentProvider` ordered ahead of
  the SDK's own by `android:initOrder`, writes the configuration into
  `Tracer.runtimeConfigs` before `Tracer.init` reads it; `Tracer.init` keeps
  what it finds there unless the `Application` implements
  `HasTracerConfiguration`, which preserves the precedence an application
  expects. Verified on a device: a default `Application` now gets a token bucket
  of 10 per hour instead of the SDK's one-shot 8, and the example's own
  `Application` still overrides it. Costs one call into a non-public SDK setter,
  which fails as a caught `NoSuchMethodError` if a future version removes it —
  see `TracerAutoConfig`.
- `TracerApplication` is now optional, and carries the same list through
  `TracerAutoConfig.defaultConfigurations()`. It stays for applications with an
  `Application` of their own, whose configuration replaces the package's.

### Fixed

- The README promised two runtime warnings where the plugin emits four: it also
  reports a `TracerOptions.appToken` and a `TracerOptions.environment` that
  were passed but are ignored on Android.

[0.2.1]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.3...v0.2.0
[0.1.1]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/KonstantenKomkov/apptracer_flutter/releases/tag/v0.1.0

[0.4.0]: https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/release-1.2.0.md
