# Task 23: runtime API coverage and logout/login investigation

Status: **completed with accepted platform limitations**, 2026-11-13.
The user explicitly accepted iOS's unsupported restart capability as a platform
limit, not a blocker for this task. Candidate versions are facade **1.2.0**,
Android **0.4.0**, platform interface **0.2.1**; no pub.dev publication is claimed.
[Completed task](tasks/development_completed_v1.md#task-23).

Release/R8 on a disposable API-35 arm64 emulator verifies four authorized
sessions in one process, same-account and different-account login, fresh
session/device identifiers, real uploads, and native writer/ANR watchdog teardown
and recreation. A second four-cycle run verifies that rejected/offline reports
are purged even with `preservePreviousReports: true` on the next start.
JVM, native and ANR reports generated **after full recreation** reached loopback
on recovery after their intentional fatal exit. This is local transport evidence,
not a claim of Tracer console delivery or manual login to a real farming account.

The [machine-readable receipt](task-23-collection-lifecycle.json) records versions,
artifacts and outcomes. `tool/check_session_recreation_receipt.py` decodes captured
multipart/gzip uploads, positively checks each session's synthetic context and
rejects any earlier account's identifiers, keys or breadcrumbs.

## SDK 1.6.1 coverage

Artifact evidence is the exact Maven Central SDK inspected in
[the audit](android-sdk-1.6.1.md) and [artifact inventory](android-sdk-1.6.1-artifacts.json).
`javap -public` and `javap -p -c` confirms the signatures and implementation behavior below.
The locally cached 1.5.2 commons API was compared again: `Tracer.enable()` and
the internal build-flag accessors are additions; no public methods were removed.
The official [1.6.1 announcement](https://t.me/tracer_changelog/185) became
accessible in the final check and was reconciled with the exact artifact APIs.
Its runtime changes are enable, manual heap/disk scheduling and the lazy heap
provider; all are mapped below. Its build changes are UUID generation with
mapping uploads disabled, configuration cache and mapping integration with
AnalyticsEnabledApplicationVariant. Those are host Gradle behavior, covered by
[the existing build verification](android-sdk-1.6.1-gradle.md), not Dart methods.
The announcement calls heap work asynchronous; bytecode/device evidence shows
that calling runNow can still suspend the VM, so the wrapper uses a worker and
does not promise uninterrupted UI. The actual builder class name is singular
`HeapDumpConfiguration`, despite the plural spelling in the announcement.

| Native API/change | Adapter and public Flutter API | Verification and limits |
| --- | --- | --- |
| `Tracer.disable()` / `enable()` | `Sdk140ConsentRuntime.pauseRuntime/resumeRuntime`; `Tracer.pauseCollection/resumeCollection` | Real SDK JVM tests, Dart/channel race tests, API-35 release/R8 loopback. Only pauses a live session. Does not purge or cancel previously admitted uploads. |
| Build/runtime disable separation | Existing build gate, surfaced by collection results | `sdk_build_disabled` cannot be overridden. Internal `$tracer_commons_release` setters are deliberately not exported as user controls. |
| `HeapDumps.INSTANCE.runNow(String tag)` | `TracerDiagnostics.run`; `Tracer.runHeapDump(tag: ...)` | Explicit module required; no auto-install/init. Nonblank tag; dispatched to an adapter worker. VM suspension remains possible. JVM/channel checks and actual public Dart release/R8 delivery: one 8,007,710-byte heap sample. Disabled provider and lifecycle gates verified. |
| `DiskUsage.INSTANCE.runNow()` / `(Context)` | `TracerDiagnostics.run`; `Tracer.runDiskUsage()` | Uses the initialized application's context through the no-argument overload; Flutter callers cannot supply an Android Context. Requests unconstrained one-time work, not a periodic schedule. Actual public Dart release/R8 delivery: one 803-byte disk sample. |
| `HeapDumpConfiguration.Builder.provideEnabled(Provider<Boolean>)` | Host installs `TracerDiagnostics.heapDumpEnabledProvider()`; Dart calls `Tracer.setHeapDumpEnabled(bool)` | Actual 1.6.1 builder/provider tested on JVM. Synchronous native provider defaults false, observes global disable, resets on full stop. Arbitrary Dart callbacks on native/fatal threads are not supported. Host must install this exact provider before SDK startup. |
| `runNow` scheduling/constraints changes | Forward to SDK without imposing old periodic constraints | `invoked` means the native void method returned, **not** that a sample was captured, admitted, uploaded or received by Tracer. SDK filters/rate limits still apply. |
| Gradle `uploadMapping`, `uploadNativeSymbols`, build disable, UUID, configuration cache and variant compatibility | Host Gradle configuration, not MethodChannel methods | Covered separately by [Gradle verification](android-sdk-1.6.1-gradle.md). Runtime calls cannot upload a build's mappings or override build disable. |

Optional diagnostic modules remain outside the managed deferred cleanup graph;
commands return `unsupported / optional_diagnostics_outside_managed_cleanup`
there. Their WorkManager jobs and already running heap operations are not covered
by managed purge or cancellation. Stopping discards queued adapter commands and
resets its heap decision; it does not claim to cancel an already admitted command.
Other backends return unsupported through additive platform-interface defaults
or a missing native operation. No optional module is a production dependency.

## Using the unreleased APIs

Use facade 1.2.0, Android 0.4.0 and interface 0.2.1 **together** from the
same repository revision (Git overrides or local paths) until publication.
Their dependency floors are updated. Merely upgrading the BOM while keeping
published Android 0.3.0 does not install this fix. Android runtime, BOM and Gradle
plugin must be exactly **1.6.1**, with deferred manifest configuration and only
the audited crash modules. iOS remains pinned to **OKTracer 1.5.2**.

```dart
// Only within an existing, authorized session:
await Tracer.pauseCollection();
// Context is retained. Events submitted while paused are discarded.
final resumed = await Tracer.resumeCollection();

// Logout, account change or consent withdrawal:
await Tracer.stopAndClearCollection();
// resumeCollection cannot reopen this session.
// Only after the application confirms the next account's consent:
final next = await Tracer.startCollection(options);
// Android deferred 1.6.1: enabled after successful cleanup.
// iOS 1.5.2: restartRequired (accepted platform limit below).
```

For optional diagnostics in an explicitly configured automatic Android host,
include its chosen heap/disk dependencies and initializer metadata itself.
In `HasTracerConfiguration`, install the heap configuration before startup:

```kotlin
HeapDumpConfiguration.Builder()
    .provideEnabled(TracerDiagnostics.heapDumpEnabledProvider())
    .build()
```

```dart
// Only after the application permits diagnostics and collection is active:
final decision = await Tracer.setHeapDumpEnabled(true);
final heap = await Tracer.runHeapDump(tag: 'manual-investigation');
final disk = await Tracer.runDiskUsage();
// Inspect state/reason. An invoked result is not a delivery receipt.
await Tracer.setHeapDumpEnabled(false);
```

The decision also affects the SDK's own heap triggers. It is an atomic native
value, not consent storage. Native applications needing arbitrary native provider
logic can keep their own provider, in which case the Dart setter explicitly
returns `heap_provider_not_installed` rather than overwriting host configuration.

## Android recreation and its boundary

The original full clear retired executors/stores, uninstalled collectors and
left SDK process caches pointing at those retired objects. Native `enable()`
only changed a flag. A direct second `TracerStartup.init` either returned without
work or rejected double initialization; the earlier reproducer establishes this
baseline, not an inherent impossibility of adapter restoration.

`Sdk161SessionRuntime` now recreates the **exact audited 1.6.1 crash-only graph**.
After writer drain, watchdog shutdown, native uninstall, purge and a main-queue
barrier, it replaces cached values in the SDK's synchronized Lazy delegates with
unevaluated factories. Final Lazy references are preserved; retired executors
and stores are never reopened. New SDK startup creates fresh configured
executors, HTTP/drop state, storage, session tags, activity/fatal handlers,
minidump writer and watchdog. Device/session identifiers are refreshed; legacy
`tracer/device_id` preferences are purged as well. Host initial custom keys are
not copied into a recreated session; the application's newly authorized Dart
options may supply current keys explicitly.

All reflective contracts are resolved before mutation and protected by R8 keep
rules. A partially initialized runtime is not marked restartable. Failed cleanup
keeps admission closed. Starts cannot cross pending cleanup or the main-queue
barrier. `stopCollection` also awaits managed teardown; pause retains context
and has a different contract. Build disable, unsupported versions, automatic
startup and optional WorkManager modules cannot use this recreation path.
This uses private SDK implementation contracts, so every SDK update requires
another bytecode/R8/lifecycle audit; matching public method names is insufficient.

## Accepted iOS platform limit and reproducer

OKTracer 1.5.2 exposes service start/stop but no verified drain/cancel/reset
completion contract. Its process crash writer and retry work can survive stop.
The existing physical-device reproducer in
[native consent acceptance](native-collection-consent.md#ios-revocation-remediation--2026-10-02-late-evening)
starts a service, immediately stops/releases it while startup work is pending,
and reproduces an `unowned` reference crash. Keeping that stopped service alive
avoids the crash; fatal-after-stop still requires sealed storage to prevent new
reports. Removing those guards for another service has not established isolation
from the retained old service and its writers.

Reproduce the supported adapter behavior with the iOS consent harness:
explicit start → stop/clear → explicit start in one process. The last result is
`restartRequired / native_restart_required`; both report paths remain sealed.
Storage tests verify purge, blocked late writes, durable marker and next-process
re-consent. **No new iOS device restart acceptance is claimed.** On 2026-11-13
the user explicitly accepted this unsupported platform capability; it does not
block task 23. Android success does not change the iOS result. A future iOS SDK
providing the needed lifecycle can be evaluated separately.

## Farming verification

The application originally resolved facade/Android 0.2.1 and BOM/plugin 1.5.2.
Its repository already stops on logout/account changes and checks remote consent
before starting again. An additional controller race reused a pending start from
the old account: stop now invalidates that cached future, and completion of the
old operation cannot clear the new account's pending operation.

Farming now uses the candidate packages together and BOM/plugin 1.6.1. The normal
application version, signing, platform variant and unrelated user changes are
preserved. `integration_test/crash_collection_lifecycle_test.dart` exercises the
actual repository, collection controller, Flutter adapter and native SDK in a
release APK. Only legal backend/network-status/secure-storage dependencies are
synthetic. The server accepts four crash uploads across users 1, 1, 2, 2; every
login waits for a new consent response, and logout disables collection.

The opt-in `tracerLifecycleAcceptance` build requires that exact entrypoint,
uses application ID suffix `.diagnostics`, debug signing, a placeholder token,
and a host configuration sending only to `127.0.0.1:38023`. Its network policy
permits HTTP only for loopback; normal payment/network configuration is unchanged.
It does not call the real auth/legal backend or inspect a user's credentials.
The repository/controller unit tests also cover pending starts and pending
consent across logout. Full farming analysis and 2680 tests pass (3 skipped).
See the receipt for the final device result.

## Reproduction and review

Build the example's consent release with SDK 1.6.1, `tracer.deferred=true`,
`tracer.verificationAnrSnapshots=true`, `target=lib/android_native_verification.dart`,
`target-platform=android-arm64`, and the checked-in `tool/android_no_upload.init.gradle`.
Set only a synthetic app token. Launch with `apptracerScenario=session-restart`
or `session-restart-offline`; use `apptracerRun` for a unique receipt ID.
Pull the app's external `files/verification` directory and run:

```sh
python3 tool/check_session_recreation_receipt.py /path/to/verification
python3 tool/check_session_recreation_receipt.py /path/to/verification \
  --scenario session-restart-offline
```

Additional scenarios: `public-pause`, `inflight`, `stop-cleanup-failure`,
`cleanup-failure`, `multi-engine`. Fatal scenarios `restarted-jvm-enabled`,
`restarted-native-enabled`, `restarted-anr-enabled` clear and re-create the runtime
before causing the fatal event. After the intentional process death, launch
`recovery` with previous-report preservation and inspect `/crash/upload`,
`/crash/uploadNative` or `/crash/uploadAnr`. For ANR, dispatch input to the blocked
Activity and use Android's **Close app** action, not force-stop; verify exit reason 6.

Separate diff review checks version/manifest/build gates, no reopening of retired
executors, new identifiers, cleanup errors, stale callback ordering, no SDK linkage,
optional module admission, and the farming pending-start race. `tool/check.sh`
covers all packages, shared native executor/storage checks, web and the example;
Android JVM tests and release/R8 device checks are recorded separately.

## Public optional Dart API acceptance

The release/R8 `android_diagnostics_verification.dart` fixture uses the optional
flavor and actual `Tracer` facade methods, channel and native modules. It starts
with Dart collection off and the native runtime disabled. Before explicit start,
heap/disk/provider-enable commands return disabled. With collection active, the
installed provider initially denies heap capture; enabling it produces exactly
one heap upload (8,007,710 bytes), while runDiskUsage produces one disk upload
(803 bytes). Turning the provider off suppresses the next dump. Pause and full
stop reject new commands; the final state is off. This checks actual uploaded
bodies, not just `invoked`. Only sizes/features are stored, never raw dumps.

The opt-in native configuration enables crash collection so the facade can use
its normal automatic lifecycle and installs the adapter's exact heap provider.
It does not change normal hosts, add production dependencies, or extend deferred
cleanup to WorkManager. The original native-only fixture remains the default for
`tracer.diagnostics=true`; the new behavior additionally requires
`tracer.dartDiagnostics=true` and the exact Dart verification target.

From the example directory, prepare the release registrant:

```sh
flutter build apk --release --config-only --target lib/android_diagnostics_verification.dart \
  --target-platform android-arm64 --android-skip-build-dependency-validation
```

Then from the repository root:

```sh
TRACER_APP_TOKEN=task23-loopback-only packages/apptracer_flutter/example/android/gradlew \
  -p packages/apptracer_flutter/example/android --no-configuration-cache \
  -I "$PWD/tool/android_no_upload.init.gradle" -PskipDependencyChecks=true \
  -Ptracer.enabled=true -Ptracer.diagnostics=true -Ptracer.dartDiagnostics=true \
  -Ptracer.uploadMapping=false -Ptracer.uploadNativeSymbols=false \
  -Ptarget-platform=android-arm64 -Ptarget=lib/android_diagnostics_verification.dart \
  :app:assembleDiagnosticsRelease
```

On a disposable emulator only, install the diagnostics APK, clear only
`ru.apptracer.flutter.apptracer_flutter_example.diagnostics`, and launch its
MainActivity with `--es apptracerScenario dart-diagnostics`. Read external
`files/verification/dart-diagnostics.json`: require `stage=complete`, final
`enabled=false` and nonempty HEAP_DUMP/DISK_USAGE uploads. No adb reverse or
external endpoint is needed; the Dart process hosts its own loopback receiver.

Task 23 has no remaining implementation/acceptance blockers in the agreed scope.
Candidate pub.dev publication is a separate release operation; farming already
uses the verified Git revision. Existing SDK/Flutter limitations remain documented.

For every future SDK upgrade, update the API table first: compare public bytecode
and official release notes, map each runtime change to the facade and platform
implementation, identify build-time settings separately, and attach positive/
negative platform evidence or an explicit open component. A successful build
alone does not establish API completeness or lifecycle recovery.
