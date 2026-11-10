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
| Already initialized, only vendor runtime flag disabled | Guarded `enable()` implemented in №15; effective crash state and handled-event recovery verified |
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

## Dependency migration (Android №14)

The Android library retains `compileOnly`; its compile/test dependencies and
the example BOM/Gradle plugin now use 1.6.1. All three VK repository declarations
were removed (library, example dependencies and plugin management). Google,
Central and the Gradle plugin portal remain in their appropriate scopes.
No optional diagnostic module was added to the application.

Version checks accept exactly 1.4.0, 1.5.2 and 1.6.1. The queue/buffer tools
recognize the new hashes; the 1.6.1 buffer check also pins the base JAR.
Consumer R8 rules already preserve the inspected names and need no additional
keep directives. Historical `Sdk140*` names remain unchanged.

Migration checks completed locally:

- 24 Android JUnit tests on 1.6.1; Android Flutter analysis and two channel tests.
- Queue, endpoint, diagnostic-buffer and fatal-handler scripts on each of
  1.4.0, 1.5.2 and 1.6.1, with matched runtime JARs.
- R8 8.10.9-dev classfile optimization of the updated plugin and 1.6.1 SDK,
  using actual consumer/vendor rules; `check_sdk140_reflection.sh` passed.
  The corresponding SDK-absent optimized plugin passed
  `check_missing_sdk_lifecycle.sh`. Libraries included Android 35, JDK 21,
  Flutter embedding, Kotlin stdlib, javax.inject and JetBrains annotations.

The reproducible APK gate is `bash tool/check_android_sdk161.sh --fresh-cache`.
It uses an empty Maven/transform cache and a separate project cache, sharing
only the Gradle executable distribution. It builds clean ARM64 release/R8 APKs
with and without SDK, with placeholder tokens, and rejects VK Maven repository
declarations. `android_no_upload.init.gradle` disables the vendor upload task
types for verification. Production mappings settings are changed separately in
№18. With Flutter 3.47.4, the gate first runs `flutter build apk --config-only`
with pub enabled: `--no-pub` also skips release registrant regeneration and
can leave a dev-only `integration_test` reference in the release Java sources.
The initial direct-Gradle run exposed that problem; after fixing the harness,
both clean APK builds passed using the same initially empty, isolated Maven
cache. No dependency/transform caches were copied from the usual Gradle home.

**Completed 2026-11-10:** 24 JUnit tests passed with no failures/skips. Both
`minifyReleaseWithR8` tasks succeeded. The SDK APK contains 60 Tracer class
definitions; the SDK-absent APK contains none and no `libtracernative.so`.
Twelve required reflection class names retain identity mappings. Neither
heap-dump nor disk-usage classes are present. Flutter targets ARM64; the SDK
additionally packages its own ARMv7/x86_64 native libraries, which does not
establish Flutter support on those ABIs. Both vendor upload tasks were SKIPPED.
The [build evidence](android-sdk-1.6.1-builds.json) records toolchain, APK hashes
and packaged libraries. This closes the build/dependency migration, not runtime
enable or device/live acceptance. Flutter's automatic AGP-9 migration flags
were not retained as part of this AGP-8 change.

Legacy hosts can retain the vendor repository in both plugin and dependency
repositories when needed:

```kotlin
maven("https://nexus-external.vkteam.ru/repository/maven/") {
    content { includeGroup("ru.ok.tracer") }
}
```

This is a legacy host configuration, not a requirement for 1.6.1. The JVM
regressions do not renew device certification of older SDK releases. Full
device acceptance of 1.6.1 remains №15/21; package versions have not been bumped
and no package was published by this migration.

## Runtime enable implementation (Android №15)

`startCollection` now observes the native state even if Dart still caches an
active session. For an initialized 1.6.1 crash runtime paused only by the host's
`Tracer.disable()`, it checks build/configuration gates, calls `enable()` via a
version-guarded reflection call, and verifies the effective crash state. A
concurrent Dart stop supersedes a pending observation/start. Repeated start
while already enabled does not reinitialize the SDK or duplicate handlers.
The normal `initialize`/state-observation paths never implicitly resume a pause.

Reasons distinguish `sdk_runtime_disabled`, `sdk_build_disabled`,
`sdk_not_initialized` and `sdk_collection_disabled`. A managed full stop remains
`restartRequired/native_runtime_retired`: revoked queues, endpoints and writers
are not recreated. Pending/failed cleanup remains blocked; an exception during
managed enable leaves collection disabled and records `native_enable_failed`.
Old audited SDKs 1.4.0/1.5.2 retain `restartRequired` for a native runtime pause.
Automatic legacy `stopCollection` stays terminal (`collection_stopped`) and
**does not establish purge guarantees**. Use the supported deferred integration
for managed stop/clear; an already automatic unmanaged runtime cannot be safely
converted to that integration within the same process.

The native release harness adds `runtime-enable`, `runtime-enable-automatic`
and `build-disabled`. It uses synthetic events and a loopback sink; uploads of
mappings/native symbols are disabled by the verification init script. The
ordinary automatic build keeps cleartext traffic disabled; only an explicit
loopback fixture enables it. No live credentials or captured payloads are
committed. `tracer.verificationBuildDisabled=true` tests the real SDK resource
without pretending that an absent SDK is a build-disabled SDK.

Validation uses SDK 1.6.1 / Gradle 8.12 / AGP 8.9.1 / Kotlin 2.1.0 / JDK 21.0.8 /
Flutter 3.47.4, an ARM64 API 35 emulator, and minified release APKs. APK hashes
and sanitized device results are in [runtime evidence](android-sdk-1.6.1-runtime.json).
JVM evidence: 31 Android JUnit tests, including seven new native resume cases;
84 facade Flutter tests, including stale Dart state and stop/start races; two
Android channel Flutter tests and analysis; the
R8 classfile reflection gate and SDK-absent lifecycle gate. The new
`tool/check_sdk_runtime_enable.sh` runs the compiled current adapter against
matched, unoptimized 1.4.0/1.5.2/1.6.1 runtime JARs; all three passed. It accepts
`compiled-plugin.jar` and the runtime classpath (commons/crash/base/manifest,
Kotlin stdlib, javax.inject, Android stubs). This verifies linkage and flags,
not on-device certification of the older releases.

Release reproduction (from `packages/apptracer_flutter/example`):

```sh
flutter build apk --release --config-only \
  --target=lib/android_native_verification.dart --target-platform=android-arm64 \
  --android-skip-build-dependency-validation
cd android
TRACER_APP_TOKEN=android-sdk161-build-placeholder \
TRACER_PLUGIN_TOKEN=android-sdk161-plugin-placeholder \
./gradlew :app:assembleConsentRelease -Ptracer.enabled=true -Ptracer.deferred=true \
  -Ptarget=lib/android_native_verification.dart -Ptarget-platform=android-arm64 \
  -PskipDependencyChecks=true -I ../../../../tool/android_no_upload.init.gradle
```

Install on a chosen emulator and launch `MainActivity` with the string extra
`apptracerScenario=runtime-enable`. Results are written under the application's
external files `verification/` directory. For automatic mode use
`:app:assembleRelease -Ptracer.deferred=false
-Ptracer.verificationApiUrl=http://127.0.0.1:37017` and scenario
`runtime-enable-automatic`. For the negative fixtures use the consent variant,
respectively `-Ptracer.verificationBuildDisabled=true` / `build-disabled` and
`-Ptracer.enabled=false` / `missing-sdk`. Start a new process between scenarios;
keep application data between `account-a` and `account-b` to exercise persisted
revocation overriding `preservePreviousReports`.

Handled-event recovery and local transport acceptance do not establish ANR
watchdog/native crash recovery or delivery/symbolication in the Tracer console.
Those remain explicit №21 acceptance; package publication is not implied.

## Optional runNow verification (Android №16)

The separate diagnostics flavor and [runtime protocol](android-sdk-1.6.1-diagnostics.md)
verify manual disk/heap work without network/charging and actual local HTTP
delivery in a fresh online run. [Evidence](android-sdk-1.6.1-diagnostics.json)
records WorkSpecs and APK hash. Observed VM/UI pauses remain several seconds
even with off-main-thread heap dumping; offline sample uploads can discard
files and return success. No optional module is added to the default graph,
public Dart API or supported deferred cleanup. Combining the optional fixture
with deferred mode fails the build explicitly.
