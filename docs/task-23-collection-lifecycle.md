# Task 23: runtime API coverage and logout/login investigation

Status: **Android recovery implemented and verified; iOS/optional acceptance
components remain open**, 2026-11-13. Candidate versions are facade **1.2.0**,
Android **0.4.0**, platform interface **0.2.1**; no pub.dev publication is claimed.
[Active task](tasks/development_v1.md#task-23).

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
The official [changelog channel](https://t.me/s/tracer_changelog) available to
the web reader currently ends at the 1.5.2 announcement; it did not provide the
1.6.1 release note. A complete release-note reconciliation remains open.
This table covers the task's named API changes, not every optional SDK module.

| Native API/change | Adapter and public Flutter API | Verification and limits |
| --- | --- | --- |
| `Tracer.disable()` / `enable()` | `Sdk140ConsentRuntime.pauseRuntime/resumeRuntime`; `Tracer.pauseCollection/resumeCollection` | Real SDK JVM tests, Dart/channel race tests, API-35 release/R8 loopback. Only pauses a live session. Does not purge or cancel previously admitted uploads. |
| Build/runtime disable separation | Existing build gate, surfaced by collection results | `sdk_build_disabled` cannot be overridden. Internal `$tracer_commons_release` setters are deliberately not exported as user controls. |
| `HeapDumps.INSTANCE.runNow(String tag)` | `TracerDiagnostics.run`; `Tracer.runHeapDump(tag: ...)` | Explicit module required; no auto-install/init. Nonblank tag; dispatched to an adapter worker. VM suspension remains possible. JVM module/configuration checks and Dart/channel tests; new wrapper's positive device delivery remains open. |
| `DiskUsage.INSTANCE.runNow()` / `(Context)` | `TracerDiagnostics.run`; `Tracer.runDiskUsage()` | Uses the initialized application's context through the no-argument overload; Flutter callers cannot supply an Android Context. Requests unconstrained one-time work, not a periodic schedule. Same acceptance limitation as heap. |
| `HeapDumpConfiguration.Builder.provideEnabled(Provider<Boolean>)` | Host installs `TracerDiagnostics.heapDumpEnabledProvider()`; Dart calls `Tracer.setHeapDumpEnabled(bool)` | Actual 1.6.1 builder/provider tested on JVM. Synchronous native provider defaults false, observes global disable, resets on full stop. Arbitrary Dart callbacks on native/fatal threads are not supported. Host must install this exact provider before SDK startup. |
| `runNow` scheduling/constraints changes | Forward to SDK without imposing old periodic constraints | `invoked` means the native void method returned, **not** that a sample was captured, admitted, uploaded or received by Tracer. SDK filters/rate limits still apply. |
| Gradle `uploadMapping`, `uploadNativeSymbols`, build disable and variant compatibility | Host Gradle configuration, not MethodChannel methods | Covered separately by [Gradle verification](android-sdk-1.6.1-gradle.md). Runtime calls cannot upload a build's mappings or override build disable. |

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
// iOS 1.5.2: restartRequired (open component below).
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

## Open iOS component and reproducer

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
re-consent. **No new iOS device restart acceptance is claimed.** The iOS part
remains open for a verified writer/task retirement mechanism and real device
acceptance; Android success does not change this platform result.

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

Open components (the full task is **not archived**):

- iOS same-process recreation and device acceptance, as described above.
- Positive release delivery through optional heap/disk Flutter commands; their
  native modules were tested separately, but invocation is not delivery evidence.
- Reconcile SDK 1.6.1 official release notes when accessible; exact artifact API
  audit and the explicitly requested methods are covered above.
- Publish candidate packages after remaining release acceptance. Git-pinned
  downstream integration can use the fix before pub.dev publication.

For every future SDK upgrade, update the API table first: compare public bytecode
and official release notes, map each runtime change to the facade and platform
implementation, identify build-time settings separately, and attach positive/
negative platform evidence or an explicit open component. A successful build
alone does not establish API completeness or lifecycle recovery.
