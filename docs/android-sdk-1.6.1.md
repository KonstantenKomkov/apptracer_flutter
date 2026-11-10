# Android SDK 1.6.1 audit — 2026-11-10

Task **Android №13** in [the upgrade plan](tasks/development_android_1.6.1.md).
This is an artifact/bytecode audit, not device or Tracer delivery acceptance.
Baseline: `138567e`, compared with the [1.5.2 audit](android-sdk-1.5.2.md).

## Distribution

The following coordinates resolve from **Maven Central**:

- BOM: `ru.ok.tracer:tracer-platform:1.6.1`.
- Marker: `ru.ok.tracer:ru.ok.tracer.gradle.plugin:1.6.1`.
- Plugin implementation: `ru.ok.tracer:tracer-plugin:1.6.1`.
- Runtime: `tracer-base`, `tracer-commons`, `tracer-crash-report`,
  `tracer-crash-report-native`, all in `ru.ok.tracer`, version `1.6.1`.
- Native dependency: `ru.ok.tracer:tracer-native-bindings:0.1.41-android`.
- Optional modules: `tracer-heap-dumps`, `tracer-disk-usage`, version `1.6.1`.

The BOM also constrains `tracer-lite-commons`, `tracer-lite-crash-report`,
`tracer-lite-performance-metrics`, `tracer-manifest`, `tracer-opentelemetry`,
`tracer-performance-metrics`, `tracer-profiler-sampling`,
`tracer-profiler-systrace`, `tracer-sample-upload` and `tracer-user-sample`.
All 16 BOM entries use 1.6.1. This does not add these modules to our plugin.

Primary sources: [BOM POM](https://repo.maven.apache.org/maven2/ru/ok/tracer/tracer-platform/1.6.1/tracer-platform-1.6.1.pom),
[plugin marker](https://repo.maven.apache.org/maven2/ru/ok/tracer/ru.ok.tracer.gradle.plugin/1.6.1/ru.ok.tracer.gradle.plugin-1.6.1.pom),
[implementation POM](https://repo.maven.apache.org/maven2/ru/ok/tracer/tracer-plugin/1.6.1/tracer-plugin-1.6.1.pom).
The [artifact inventory](android-sdk-1.6.1-artifacts.json) records exact URLs
and SHA-256 for the downloaded POMs, Gradle metadata, AARs and plugin JAR.
Vendor binaries are not committed.

An independent Gradle 8.12 project resolved the crash/native/heap/disk graph
and plugin marker transitively, using only `google()` and `mavenCentral()`
(48 resolved artifact entries). It used the existing Gradle cache; the fresh
cache Android/Flutter builds required by №14 remain a separate check.
The optional diagnostic graph includes WorkManager 2.7.1 and
`tracer-sample-upload:1.6.1`; these are outside the crash-only consent adapter.
Plugin dependencies include Kotlin stdlib 1.8.22, JavaPoet 1.13.0,
HttpClient/HttpMime 4.5.14 and Jackson Core 2.14.3. AndroidX still needs Google
Maven; moving Tracer to Central does not eliminate Google's repository.

## Compatibility and inspected contracts

The inspected runtime AAR manifests retain **minSdk 21**. Their AAR metadata
declares `minCompileSdk=1`, `minAndroidGradlePluginVersion=1.0.0`; these are
metadata lower bounds, not a tested toolchain matrix. The plugin has Java 11
classfiles (major 55). Our example uses Gradle 8.12, AGP 8.9.1, Kotlin 2.1.0;
the Android library declares AGP 8.5.2/Kotlin 1.9.24 and compileSdk 35.
Local checks use JDK 21.0.8. A separate minimal Android application passed
`assembleDebug` with Gradle 8.12 / AGP 8.9.1 / Kotlin 2.1.0 / compileSdk 35 /
minSdk 21, SDK 1.6.1 and both uploads disabled, without a plugin token.
The API probe compiled calls to `Tracer.disable()` and `Tracer.enable()`.
The fixture enables `android.useAndroidX=true`. AGP 9 is not certified by this audit.

Compared `javap -p -c` output against cached 1.5.2 binaries, normalizing only
constant-pool indices. These relevant implementations are unchanged:

- `CoreTracerConfiguration`, `TracerInitializer`, `SequentialExecutor`,
  `TracerThreads`, `TagsStorage`, `SessionStateStorage`, `TracerFiles` and
  `ChainedUncaughtExceptionHandler`.
- `CrashReportInitializer`, `ExitReporter`, `TracerUncaughtExceptionHandler`,
  `CrashLoggerInternal`, `TracerCrashReport`, `LogStorage`.
- `ProcessUtils` and `AppTokenUtils`.

The existing reflection fields, queue owner, terminal storage states and
initializers remain present. Crash/commons/native manifests introduce no
additional initializer in the supported crash graph. Heap/disk initializers
remain outside the adapter allowlist. Native bindings retain
`Minidump.getInstance()` and `uninstallMinidumpWriter()`; a Java signature
check is not a JNI uninstall/reinstall test.

`Tracer` replaces private `isDisabled` with volatile `disabledOnBuild` and
`disabledInRuntime`. `isDisabled()` combines both. `TracerStartup` now sets
the build flag when build-time configuration disables initialization.
The fatal-handler JVM fixture must use the new runtime field on 1.6.1;
production cleanup does not reflect into that field.

The watchdog now checks `Tracer.isDisabled()` before saving an ANR snapshot.
That branch returns before scheduling the next snapshot. Do not infer complete
ANR recovery from a successful handled-event disable/enable cycle: №15/21
must verify it on-device. Tombstone/exit-report logic is unchanged from 1.5.2;
API 31+ opt-in and purge-before-start requirements still apply.

## Runtime enable decision

The exact API is `public static final void Tracer.enable()`.
It returns without changing runtime state when `disabledOnBuild` is true;
otherwise it clears `disabledInRuntime`. It performs **no initialization**,
executor creation, queue restoration, handler installation or file recovery.
`disable()` sets only the runtime flag. Initialization remains one-shot.

| State | Policy for the Flutter adapter |
| --- | --- |
| Already initialized, only vendor runtime flag disabled | Eligible for guarded `enable()` in №15; verify effective crash-module state and new events |
| SDK absent or build-time disabled | Remain disabled; never claim enabled or initialize through `enable()` |
| Deferred, never started | Use the existing authorized startup path; never bypass it with `enable()` |
| Managed `stopCollection` after startup | Keep `restartRequired`: executors/endpoints are permanently revoked, watchdog stopped, fatal/native writer detached, stores cleared |
| Cleanup pending or failed | Remain blocked/error; `enable()` cannot erase a purge obligation |
| 1.4.0/1.5.2 host | Keep existing behavior; never link/call the new method unguarded |

Policy: retain the exact 1.4.0 and 1.5.2 allowlist entries. Add 1.6.1 only with
the matching artifact hashes, adapted fixture and build checks in №14.
Do not accept arbitrary 1.6.x versions. This audit supports retaining the
existing full-stop semantics; it does not promise recovery after destruction.

## Optional diagnostics: corrections to announcement assumptions

The class is **`HeapDumpConfiguration`**, singular. Its builder exposes
`provideEnabled(javax.inject.Provider<Boolean>)`; `setEnabled(boolean)`
wraps a fixed provider. `build()` stores the provider without evaluating it.
The internal enabled getter evaluates it on each read and catches `Exception`
(including a null-result failure), returning false. It does not catch every
`Throwable`. `HeapDumps.runInternal` reads it on the calling thread after
checking the global disabled flag. This is a pull-based decision, not a
subscription; a custom `HasTracerConfiguration` retains ownership.

**`HeapDumps.INSTANCE.runNow(String tag)` synchronously calls
`Debug.dumpHprofData` through `runInternal`.** It rejects blank tags and uses
an atomic admission flag. Only the subsequent shrink/upload work is queued.
Thus the original plan's assumption that both diagnostics are asynchronous
needs qualification: a host wrapper must dispatch heap dumping off the UI
thread, and Android heap dumping can still pause the VM. Do not promise a
nonblocking UI solely because WorkManager processes the resulting dump.

`DiskUsage.INSTANCE.runNow()` creates a one-time WorkManager request without
constraints and passes `put_constraints=false`; an overload accepts an
application context. Heap `runNow` passes false into shrink/upload scheduling
and likewise creates an unconstrained one-time shrink request. Periodic disk
work still requests device idle, unmetered network and battery-not-low.
№16 must verify both execution and subsequent delivery separately; no blanket
consent guarantee is established for optional WorkManager jobs by this audit.

## Gradle DSL and mappings

The actual DSL is **`uploadMapping`**, singular, with a merged default of true.
Native symbols use independent `uploadNativeSymbols`. `hookVariant` generates
a time UUID only when the SDK is not build-disabled, minification is enabled
and `uploadMapping` is true. Otherwise the application resource
`tracer_mapping_uuid` uses the fixed all-zero UUID; absence of a random UUID
does not imply absence of the resource. This is not a claim of reproducible APKs.

The plugin checks concrete `ApplicationVariantImpl`/`LibraryVariantImpl`, then
the public `ApplicationVariant`/`LibraryVariant` interfaces. The latter branch
can handle an analytics wrapper implementing the application interface;
there is no new application analytics feature. №20 must reproduce that branch
and verify variant-specific mapping selection. Configuration-cache reuse and
invalidation still require execution in №19; bytecode inspection alone is
insufficient. No upload tasks were invoked during this audit.

## JVM evidence and remaining acceptance

Extracted 1.6.1 `classes.jar` SHA-256:

| Module | SHA-256 |
| --- | --- |
| commons | `3be4caa6cfea92c7f3e44eb191c1ef0a8ad3e9cbc831839aee119fbcdc8a4d67` |
| crash-report | `a97c68cdc9eabce8d04be28eb5ea18b739ed848bdc6f6f50a70cbd4a9b333258` |
| base | `b0331c5a4eeedf279b2abc80d4ea42067b4e4ea844f90a966b18a4a508e935e6` |
| native-bindings | `32c82515f8a695ad148473ec3ad7e0cb162502c45bd44cc6b6ebe5daf7ab010a` |

Ran the existing Java main-based tests against an exclusively 1.6.1 runtime
classpath, Kotlin stdlib 2.1.0, javax.inject 1 and Android 35 stubs:
6 executor lifecycle checks, 6 vendor queue checks, endpoint revocation,
3 store checks, 5 fatal admission/drain checks, diagnostic deletion and all
reflection names/native signatures. All passed. Audit-only copies of the
fatal fixture and reflection version assertion were adjusted for 1.6.1;
the original fatal fixture fails with `NoSuchFieldException: isDisabled`.
Production version/hash gates were not relaxed as part of the audit.

Reproduction uses the source tests in
`packages/apptracer_flutter_android/android/src/test/java/ru/apptracer/flutter`,
compiled with `javac -cp <extracted-sdk-jars>:<stdlib>:<inject>:<android.jar>`
together with their adapter helpers, then runs each test's `main` with `java`.
The maintained `tool/check_sdk140*` commands are updated in №14.
Full Flutter release/R8, fresh-cache resolution, device lifecycle, delivery,
duplicates and Java/Kotlin symbolication remain explicit acceptance in №14–21.
