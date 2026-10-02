# Native collection lifecycle: verified implementation

Status, 2026-10-03: the Android SDK 1.4.0 and OKTracer 1.5.2 adapters are
implemented. Physical iOS acceptance is complete, including native symbolication.
Android release/R8 on API 35 has passed cold/offline/in-flight/account/engine,
native and JVM revocation, real ANR recovery, missing SDK/token and injected cleanup failures.
ANR, native SIGSEGV and JVM fatal delivery are confirmed in the dashboard.
JVM/ANR names are readable after R8; native minidump symbolication remains partial
as detailed below. The tested collection/revocation acceptance is complete.
Web/HTTP stop now clears account data and recreates its owned client on restart;
VM/Chrome lifecycle and release browser tests pass. Anonymous V8 frame locations
are now preserved. Source maps were uploaded before the corrected release probe;
the user confirmed a readable anonymous Dart application frame in the dashboard.
Historical sections retain earlier failures and their subsequent fixes.

The six publishable packages and internal constraints are prepared for stable
`0.2.0`; the local Sentry transport remains `publish_to: none`. This preparation
does not publish packages or migrate Garden applications. Earlier `0.2.0-dev.1`
references below describe the verification builds.

## Dart contract

```dart
await Tracer.initialize(
  options: const TracerOptions(
    nativeInitialization: TracerNativeInitialization.deferred,
    iosAppToken: 'your-ios-token',
  ),
  appRunner: () => runApp(const MyApp()),
);

// After the application has verified consent and its account applicability:
final started = await Tracer.startCollection();
if (started.state == TracerCollectionState.restartRequired) {
  // Explain that collecting again requires a new process. Do not loop initialize.
}

// On withdrawal, logout or account change:
final stopped = await Tracer.stopAndClearCollection();
// Treat error/unsupported as a failed native stop/purge, not as success.
```

Bootstrap invokes `appRunner` once per bootstrap call. `startCollection` never
runs it or creates a zone. Do not call bootstrap again to toggle diagnostics.
`isCollectionEnabled: false` rejects Dart collection; it does **not** remove Android
startup providers. Explicit starts with disabled options do not authorize native
collection. Only successful starts permit Dart errors, logs, keys and breadcrumbs.
Values supplied while off are discarded. Each fresh start applies only the explicitly
supplied `initialCustomKeys`. Stop clears Dart keys, breadcrumbs and deduplication
immediately, even when native work is pending or fails. Lifecycle calls are serialized;
a late start response cannot reinstall handlers or permit events after a stop command.

`TracerCollectionResult` distinguishes `enabled`, `disabled`, `restartRequired`,
`unsupported` and `error`, and carries a diagnostic `reason`. Observing native state
never grants Dart permission. A failed purge does not prove that native traffic stopped.
Legacy `stopCollection` remains available and does not promise native report deletion.

## Android build-time setup

The host manifest must remove **both** providers before the process is launched.
Keep the vendor's **application-level initializer metadata** and Gradle resources;
removing metadata would prevent starting crash/native modules later.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">
  <application>
    <provider android:name="ru.ok.tracer.startup.InitializationProvider"
              tools:node="remove" />
    <provider android:name="ru.apptracer.flutter.TracerAutoConfigProvider"
              tools:node="remove" />
  </application>
</manifest>
```

Check the merged release manifest: neither provider may remain enabled, and no custom
Application or other provider may call SDK startup. The runtime preflight rejects a
manifest that still declares either provider. Automatic mode retains the existing
provider-driven integration; it offers no pre-consent guarantee. No manifest defaults
were changed for existing integrations. SDK absence is reported as unsupported;
an empty or missing Gradle `tracer_app_token` fails startup.

The Android adapter supports the inspected SDK **1.4.0**, in the main process, with
logger/core/crash and optional native-bridge initializer metadata. An unverified SDK,
extra initializer, missing metadata, missing token or prior SDK startup fails the start.
The adapter uses `TracerStartup.init` to preserve dependency ordering. It provides an
SDK-only Application context that retains the host's feature configurations and dynamic
core token/endpoint providers, wraps custom IO/background executors, and tracks the
SDK's activity callbacks for removal. The host Application itself remains unchanged.
Automatic startup retains the existing provider-driven integration. A purge on an
unmanaged automatic runtime reports an error, since its senders cannot be tracked.

Default deferred startup discards previous-process diagnostics before configuring or
starting senders. `preservePreviousReports: true` is an explicit application decision
that the prior reports belong to the same authorized account/session; it permits crash
recovery upload after a fatal crash. A persisted purge obligation overrides preservation.
Stop records that obligation before asynchronous cleanup and retains it even after
successful deletion. Only the next authorized deferred start can clear the obligation,
after clearing previous files and before starting senders. This also forces deletion of
files from a callback already running at revocation or a process death during cleanup.
It is not legal consent storage.

Stop closes executor wrappers, revokes the SDK's additional sequential background
queue, and removes SDK activity callbacks immediately. It waits
for active executor work and synchronous Java crash writers, stops the inspected ANR watchdog and uninstalls the optional
native minidump writer before retiring native diagnostic stores and deleting the
main-process `cacheDir/tracer` root. It restores the prior exception handler only if
SDK's installed handler is still current. Native log/tag lists, session/system-state
references, the initialized session file-cache map and copied initial keys are cleared.
The SDK's retired session store cannot reload disk diagnostics. Host-owned configuration
maps and executors remain owned by the application. Timeout, marker failure, collector
failure, buffer retirement failure or deletion failure returns `error`. A successful stop
after SDK initialization returns `restartRequired`; a never-started SDK returns `disabled`.
Starts cannot run while cleanup is pending, and a new engine cannot reset this process state.

Already active requests are not claimed cancelled. The controlled endpoint returns an
empty relative address after revocation: the inspected SDK URL client rejects it before
opening a connection. Throwing from that provider is insufficient because the SDK catches
provider exceptions and falls back to its default Tracer address. An address selected
before revocation may still reach a request; cleanup waits for active work. The release/API-35 offline and held-response tests below establish the tested
device behavior.
Private watchdog fields and native writer method names are version-bound and protected
by consumer R8 rules. The API-35 release/R8 verification is recorded below. An SDK upgrade requires
repeating these checks against the new artifact.

## Vendor evidence collected locally

The following artifacts were inspected on 2026-10-02. Inspection is **not** a device
verification of revocation. No device was attached at the start of this work.

| Artifact | Observation |
|---|---|
| `tracer-commons:1.4.0`, `classes.jar`, `javap -p -c ru.ok.tracer.Tracer` | `disable()` only writes `isDisabled=true` and logs. It invokes no cancellation, shutdown or deletion. `init$tracer_commons_release` is one-shot. |
| Same AAR, `AndroidManifest.xml` and `InitializationProvider` bytecode | Provider calls `TracerStartup.init(context)`. Logger/core initializer metadata is at application level. |
| `tracer-crash-report:1.4.0`, `TracerCrashReport.init$lambda$0` / `CrashUploader` bytecode | Startup queues background work that proceeds to upload saved reports; this runnable does not recheck the disable flag. Deleting a directory while it runs cannot establish revocation. |
| `tracer-commons:1.4.0`, `CoreTracerConfiguration.Builder` / `TracerThreads` | Public custom IO/background executors exist. An adapter controlling them is a possible next step, but it must also handle direct crash uploads, native writer, ANR watchdog and activity callbacks. The adapter is now implemented; its device/runtime guarantees are not yet verified. |
| `TracerFiles`, `CrashStorage`, `LogStorage`, `SessionStateStorage` bytecode | Main-process diagnostics reside under `cacheDir/tracer`; other processes have separate roots. Includes crashes, logs, minidump and session data. Purging only Dart logs is insufficient. The adapter deletes the main-process root after quiescence; helper checks do not establish device quiescence. |
| `tracer-native-bindings:0.1.14`, `Minidump` bytecode | `uninstallMinidumpWriter()` exists. It alone does not stop Java/ANR collection or uploaders. |
| `OKTracer:1.5.2`, public arm64 `.swiftinterface` and `Podfile.lock` | `TracerServiceProtocol` exposes `start`, `stop`, delegates, setters and sends, but no queue/report purge or network cancellation method. Restart and stop semantics cannot be inferred from the method names. |

SHA-256 of extracted `classes.jar`: commons
`ee7964358a1385c2fc38d362e7e49aa2e61a1998a3c8992ad4f61f1f03381782`, crash-report
`aeffc371b708e60032942074603aeaa1d8aa9c77e0442e332408bf71c46bf6dd`.
SHA-256 of OKTracer 1.5.2 public `arm64-apple-ios.swiftinterface`:
`686ccba10401034089a9ed3978ccd11b43bafc5c7b85f3ed7202831e8c8731ec`.

## Remaining native guarantees and report policy

Android plugin state is process scoped; engine detach does not reset a stop. iOS now
shares its service, log provider and delegate across plugin instances. Repeated automatic
initialize reuses the service. Stop detaches the delegate and clears Dart logs; a later
start reports unverified restart capability rather than creating another service.
Neither this nor a `stop()` call proves vendor queue deletion or cancellation.

The implemented report policy discards earlier launch reports by default, permits
explicit preservation for an application-verified original session, and overrides it
with a persisted purge obligation. Device acceptance must still prove offline → stop →
online and crash → new process, including account metadata, logs and breadcrumbs.
Native SDK buffer retention and late callbacks remain part of the runtime audit.

Already delivered server reports cannot be removed by a local purge. Requests already
begun must be distinguished from newly dispatched sends. Current SDK inspection provides
no proof that either SDK cancels active requests. No such cancellation is promised.

Other federated backends inherit compatible default methods: automatic start uses their
existing initialize and query reflects their enabled flag. Sentry purge still reports
unsupported after stopping. HTTP/Web now supports explicit start and in-memory cleanup;
it recreates an owned HTTP client on re-consent and discards logs, keys and user ID.
Other backends remain unsupported unless overridden. No unverified persisted-queue
cleanup is implied by the fallback.

## Verification update — 2026-10-02

The native processes launched earlier are terminal; their handles no longer exist.
The Gradle 8.12 download failed to unzip, so that Android platform test run provides
no lifecycle proof. The earlier iOS build found a static-service reference error;
that source error has been fixed. A direct Swift compiler typecheck against the
cached Flutter framework and OKTracer 1.5.2 simulator framework now succeeds.
This is compile evidence only, not an iOS device acceptance run.

`RevocableExecutor` now implements queue revocation, drops queued callback payloads,
and refuses to claim quiescence before revocation. `bash tool/check_native_executor.sh`
passes five JVM checks (queued/future work, active-work drain, throwing callback,
synchronous host executor, and prohibition of cleanup on an open executor).
It is included in the monorepo check command. At that check it was not yet wired into SDK startup. The later adapter update below
adds that wiring; helper checks still do not prove SDK sender shutdown on a device.

Direct Dart analysis of the main and platform-interface packages passes. New regressions
cover disabled options during an active start and removal of initial account keys before
a restart without new options. Their latest execution is pending: the current sandbox
refuses the Flutter test runner's localhost socket (`SocketException`, operation not
permitted). Earlier 76 main-package and 41 interface tests passed before these additions.
Full Xcode rebuilding is also unavailable in the current sandbox: CoreSimulatorService
connections are refused and xcodebuild rejects the workspace. No new runtime or R8
acceptance is inferred from these limitations.

## Android adapter update — 2026-10-02

`ConsentTracerApplication`, `Sdk140ConsentRuntime` and `DiagnosticFiles` now connect the
executor gates to SDK startup and the Flutter method channel. All Java sources and the
Kotlin plugin compiled against the inspected 1.4.0 JARs, Android 35 API and Flutter
embedding, using javac and Kotlin 1.9.24. `check_native_executor.sh` now passes six executor
checks and file-purge checks covering nested reports, external symlinks, dangling links,
a linked root and repeated cleanup. The dangling-link check caught an actual cleanup bug,
which was fixed. This is compile/helper evidence, not Gradle, R8 or device acceptance.
The main/interface Dart analysis passes after adding `preservePreviousReports` and
clearing that permission on stop. Native collector shutdown, report delivery and SDK
buffer/late-callback behavior remain unverified until the specified runtime scenarios run.

## SDK background queue audit — 2026-10-02

The inspected `TracerThreads$bgExecutor$2` wraps a supplied executor in its own
`SequentialExecutor`. Closing the supplied executor alone leaves its queue holding
captured diagnostics; an already running vendor queue runner can consume further tasks.
`Sdk140BackgroundExecutor` now installs a revocable view over that original queue before
the first runner reaches the host executor. Revocation clears the original queue and
rejects subsequent additions and polls. It leaves an already polled task to drain,
so it does not claim cancellation of active work. A binding failure revokes executors,
reports a lifecycle failure and prevents cleanup from claiming a successful drain.
The queue and runner fields used reflectively have consumer R8 keep rules.

`tool/check_sdk140_background.sh` accepts the extracted commons JAR and Kotlin stdlib,
requires the commons SHA-256 recorded above, and runs six tests against the actual vendor
class. These verify pending payload removal (including the underlying queue), rejection
of future reports, revocation during an active runner, synchronous host executors,
revocation before first submission, and failed binding without an uncaught production
exception or false successful drain. All six pass. The executor/file helpers also pass,
and the Android Java/Kotlin sources compile against cached SDK/Android/Flutter artifacts.
This evidence does not cover native log/key buffers, delayed main-loop callbacks, device
network behavior, fatal recovery or release R8. Those acceptance requirements remain open.

The same standalone helper checks are called by `NativeLifecycleHelpersTest` in the
existing Gradle unit-test/CI job. This wrapper has not been executed locally: JUnit is
absent from the current Gradle cache and a full Gradle run remains unavailable. The
successful runs above used the standalone script, not that JUnit wrapper.

To repeat the pinned SDK queue check:

```sh
bash tool/check_sdk140_background.sh /path/to/tracer-commons-1.4.0/classes.jar /path/to/kotlin-stdlib.jar
```

## Native diagnostic store and endpoint audit — 2026-10-02

`Sdk140DiagnosticBuffers` retires the SDK's stores after executor drain, watchdog exit,
native writer uninstall and exception-handler restoration. It clears the current log
deque under the SDK's deque monitor and resets its byte counter; detaches previous logs
and tags and marks them clean; clears current tags; drops current/previous system/session
objects and history; and replaces the already initialized `SimpleFileKeyValueStorage`
map with an empty map. It never initializes that lazy map while erasing it. The retired
session storage is marked loaded so it cannot resurrect files. Copied core initial keys
and its copied token-provider callback are released without changing the host's config.
The endpoint separately releases its reference to the host core config on revocation.
A new collection period requires a new process. This is terminal retirement, not an
attempt to make the vendor singleton restartable.

`Sdk140Endpoint` fixes the SDK's exception fallback: throwing from an endpoint provider
returns the SDK's default address, so the revoked provider instead returns an empty,
non-null address. The actual `CoreTracerConfiguration` getter accepts that value without
fallback, and the inspected `HttpUrlConnectionHttpClient.execute` calls `new URL(...)`
before `openConnection`, rejecting the relative address. A request whose address was
selected before revocation is still considered active; socket cancellation is not claimed.

`tool/check_sdk140_buffers.sh` validates commons/crash JAR hashes and runs the endpoint
regression and three diagnostic store checks against actual SDK classes. All pass:
loaded log/tag/session/key stores are retired, repeated cleanup succeeds, an uninitialized
file map is never loaded, and an incompatible store fails cleanup. Test-only allocation
bypasses Android constructors to populate actual vendor fields without starting collectors;
this tests store retirement, not the Android lifecycle. The Java/Kotlin production sources
compile with the new adapter. `NativeLifecycleHelpersTest` also calls these checks in the
existing Gradle suite; that wrapper still lacks a local execution result.

To repeat the store/endpoint checks, supply the inspected extracted JARs, Kotlin stdlib,
Android API JAR and javax.inject JAR:

```sh
bash tool/check_sdk140_buffers.sh commons.jar crash.jar base.jar kotlin-stdlib.jar android.jar javax.inject.jar
```

The new JVM evidence does not close device network, fatal recovery, delayed callback,
JNI writer cleanup, R8 or iOS acceptance. Those requirements remain open.

## R8 classfile verification — 2026-10-02

R8 **8.10.9-dev** from Android build-tools 36.0.0 processed the current compiled
Java/Kotlin plugin, inspected commons/crash/base/native-bridge 1.4.0 JARs and native
bindings 0.1.14. Inputs included the real plugin consumer rules and the vendor AAR
`proguard.txt` rules, with Android 35, Flutter embedding, Kotlin and javax.inject as
libraries. The run used `--release --classfile` and exited successfully. No extra
keep rules were supplied for the test fixtures.

The optimized classfile JAR passes `tool/check_sdk140_reflection.sh`: six executor
checks, six vendor queue checks, file deletion checks, exact reflected startup/queue/
buffer/watchdog/JNI method names, and three actual SDK diagnostic-store checks. The
fixtures resolve model types through retained store fields, so obfuscated model names
do not receive artificial protection. This checks real consumer-rule behavior for
Java reflection and store retirement after optimization.

A separate R8 run containing the plugin and no vendor program classes also succeeds.
`tool/check_missing_sdk_lifecycle.sh` passes against that output: state is
`unsupported/sdk_missing`, disabled starts and events do not activate the SDK, and
another plugin instance preserves the absence of collection after stop. This smoke
check does not invoke Android logging, engine attachment or JNI on a JVM, and does
not establish missing-SDK APK behavior on a device.

To repeat the optimized-class checks:

```sh
bash tool/check_sdk140_reflection.sh optimized-with-sdk.jar kotlin-stdlib.jar android.jar javax.inject.jar
bash tool/check_missing_sdk_lifecycle.sh optimized-without-sdk.jar flutter.jar android.jar kotlin-stdlib.jar
```

For those inputs, run R8 in classfile mode over current compiled plugin classes,
with the plugin consumer rules and extracted vendor rules. Add the inspected SDK
JARs as program inputs for the first run; omit them from both program and library
inputs for the second. Supply JDK classes, Android API, Flutter embedding, Kotlin
and javax.inject as libraries. Preserve the R8 version, mapping and output log when
comparing an SDK/toolchain upgrade.

These results are narrower than the task's Android release gate. They do not verify
APK/Dex packaging, manifest merging, JNI linkage, crash/ANR collection or runtime
network behavior. The full release build and device acceptance remain outstanding.

## Synchronous fatal writer audit — 2026-10-02

The Java fatal reporter saves diagnostics synchronously, outside the configured executor
queues. `Sdk140FatalHandler` now replaces only the diagnostic handler at the front of the
inspected SDK `ChainedUncaughtExceptionHandler`, retaining its forwarding to the existing
application/OS handler. Revocation prevents new entries and releases the writer reference.
Cleanup waits for admitted fatal writers before retiring buffers or deleting files. A
throwing writer still releases admission and lets the vendor chain forward the fatal.

Crashes can enter the vendor handler during startup, before its chain is wrapped. The
adapter snapshots threads already inside the inspected SDK fatal/chain frames and waits
for those calls to leave, in addition to its admission counter. Names involved in this
version-bound stack tracking are protected by consumer rules. An unrecognized handler
chain, timeout or inability to inspect these calls fails cleanup; no successful purge is
claimed. The application/OS still controls process termination.

Five checks pass against the actual vendor chain and fatal serializer, both before and
after R8. They cover revoked admissions, active-writer drain, exception propagation,
single host forwarding after revocation, and a serializer entered during startup outside
the new counter. The startup fixture uses an uninitialized SDK store to prevent disk
writes and a blocking throwable to hold the real serializer frame. This is Java lifecycle
evidence, not a fatal crash recovery test on Android or a JNI minidump test.

The native stop path closes admissions first, persists the purge obligation, and then
unregisters host callbacks. SDK disable runs even if callback removal or marker persistence
throws. A host callback-removal failure therefore cannot erase an already persisted
revocation obligation. Successful cleanup retains that marker until authorized startup.
The production Java/Kotlin sources compile, and optimized with-SDK/no-SDK classfile checks
pass with the new handler control. Device/network/APK/JNI acceptance remains open.


## Device verification harness — 2026-10-02

The example has a separate `lib/consent_main.dart` entrypoint. It bootstraps deferred
collection without network warmup, exposes start/query/stop-and-clear, labels synthetic
users through `TRACER_TEST_USER`, and provides explicit Dart/JVM/SIGSEGV/ANR probes.
The `consent` Android flavor is enabled only with `tracer.deferred=true`; its separate
application ID ends in `.consent`. Its manifest overlay removes the vendor and plugin
startup providers while retaining SDK application metadata. Source XML was checked;
merged APK manifest and device behavior remain unverified.

From the repository root, fill the ignored `.env.tracer` with the Android app and plugin
tokens belonging to the same active Tracer project. The user authorized using farming's
Tracer project for acceptance after deleting the earlier project. Existing farming
configuration was inspected without printing token values; validity and delivery have
not been tested. Loading this file into the current shell makes the tokens available to
Gradle (the file is not loaded automatically):

```sh
source .env.tracer
cd packages/apptracer_flutter/example
env 'ORG_GRADLE_PROJECT_tracer.deferred=true' \
    'ORG_GRADLE_PROJECT_tracer.enabled=true' \
    flutter run --flavor consent --target lib/consent_main.dart \
    --dart-define=TRACER_TEST_USER=consent-test-A
```

Flutter receives Gradle project properties through these environment variables.
For the device integration test, use the same two flags with
`flutter test -d DEVICE --flavor consent integration_test/native_consent_test.dart`.
For the SDK-absent variant, omit `tracer.enabled` and add
`--dart-define=TRACER_EXPECT_SDK=false` to the test command; no tokens are required.
The integration test covers the actual lifecycle channel, immediate Dart revocation,
buffer clearing, and single appRunner invocation. It does not prove disk/network cleanup,
server delivery, or fatal recovery.

Manual acceptance still requires files and traffic before/after permission, offline
revoke followed by network restoration, Java and JNI fatal recovery in a new process,
account changes, concurrent operations, engine/Activity recreation, cleanup failures,
and an obfuscated release APK with retained merged manifest/mapping/symbols. Explicit
fatal probes terminate or stall the test app. A new process is required after SDK stop;
preserve previous reports only for an explicitly authorized same-account recovery test.

Local verification: Dart analysis of the new entrypoint and integration test passed.
The example MainActivity also compiles directly against the cached Android/Flutter
classpath, including the explicit JVM fatal probe. This is not an APK build.
ADB cannot bind its local daemon socket (`Operation not permitted`). The SDK-absent
release build reached `assembleConsentRelease` but failed creating Gradle 8.12's wrapper
lock outside the writable workspace. No APK or device/server result was produced.
The cached Gradle 8.12 distribution was separately inspected with Python ZipFile:
its central directory is invalid (`BadZipFile: File is not a zip file`). Moving
GRADLE_USER_HOME to a writable directory cannot reuse this damaged archive.
Tokens alone do not resolve these local execution restrictions.


## Prerelease package preparation — 2026-10-02

All seven packages are prepared at `0.2.0-dev.1`, with matching internal caret
constraints and example dependencies. Their changelogs describe the lifecycle
contract and platform limits. Offline dependency resolution with the repository's
path overrides and Dart analysis passed for all seven packages and the example.
This proves local dependency/source consistency, not resolution of unpublished
packages from pub.dev. No release or publication was performed. Full monorepo
unit/browser/native/build checks and device/server acceptance remain required.

Existing integrations retain automatic initialization by default. To opt into
Android deferred mode, remove both startup providers in the application's manifest,
retain SDK metadata/resources, bootstrap with deferred options, and authorize only
through startCollection. Setting a Dart flag alone cannot stop Android providers.
After stop-and-clear, inspect the result and require a new process when it reports
restartRequired. Deferred iOS collection remains unsupported until verified native
cleanup is available. HTTP/Sentry/web implementations do not implement native
collection lifecycle operations. These limits are part of the migration contract;
updating dependencies does not authorize collection or enable application release flags.


## Credential-backed build attempts — 2026-10-02

The user filled all six Android/iOS/Web token variables in ignored `.env.tracer`.
Only presence was printed; token validity has not been established. Make targets now
prefer that local file (falling back to the historical ~/.tracer-env), print only token
presence, and pass Android Gradle properties through the environment.

With these credentials loaded, the ordinary Web release example built successfully
with source maps (`build/web/main.dart.js` and `.map`). Its optional Wasm dry run emitted
a telemetry-file permission warning; the JavaScript build completed with exit 0.
This is compilation evidence, not browser execution or delivery/dashboard evidence.
No report is claimed delivered from this build.

The Android consent release attempt exited 1 before compilation because the Gradle
wrapper could not write its cache lock. ADB again failed to bind its daemon socket.
The iOS unsigned release build exited 1 during package resolution because Swift module
and package diagnostic caches outside the workspace were not writable. simctl also
could not connect to CoreSimulatorService. No device tests ran and no Android APK or
iOS app was produced by these attempts. The missing-token blocker is resolved; the
execution-environment blockers and full acceptance gates remain.


## Unrestricted-session verification — 2026-10-02

Session permissions changed to full filesystem/network access. ADB and simctl now
work. Android API 35 `Medium_Phone_API_35` and an iOS 18 iPhone 16 Pro simulator
were started for actual device-channel tests. The damaged Gradle 8.12 archive was
retained as `.zip.invalid-20261002`, allowing the wrapper to download a new copy.
The Android release build is still running; no success is claimed yet.

Monorepo checks now executed rather than failing at socket creation. Formatting and
analysis passed, and all Dart/browser suites passed: platform interface 41, HTTP 13,
Sentry 23, Android registration 2, iOS registration 2, Web browser 5, facade 78,
example 1 (165 tests total). The check script's exit 1 came from publish dry-run
warnings about modified tracked files, with hints about local path overrides. This
is not a native Gradle/Xcode test result or device/file/network acceptance.

The initial iOS device test reached Xcode but failed on the example's old deployment
targets under Xcode 27. The example now uses iOS 15 for Runner/framework and raises
older Pod targets to that floor. This changes only the example; the plugin's iOS 13
requirement remains. A device test additionally verifies deferred refusal through
the real iOS channel, discarded Dart diagnostics, one bootstrap, and honest cleanup
error reporting. It does not establish successful native cleanup or delivery.


The iOS deferred device test passed on the iOS 18 iPhone 16 Pro simulator after
updating the example's deployment targets: one executed test, Android case skipped.
It verifies actual native refusal, Dart diagnostics discarded while off, one appRunner,
and cleanup error reporting without false re-enablement. This does not prove successful
native cleanup, report delivery, disk contents or network silence; those acceptance
requirements remain open. The simulator log is `/tmp/apptracer-ios-consent-device.log`.


The ordinary Web live verification test passed through Flutter drive and ChromeDriver
in Chrome 154 using the filled JS project token. Three reports (caught FormatException,
synchronous StateError, build StateError) received HTTP 200 from Tracer. The test also
verified Dart reporting stops after revocation. This establishes request acceptance,
not dashboard display/grouping or native lifecycle guarantees. Dashboard checks for
three groups, breadcrumb and checkout_step=3 were requested separately. Log:
`/tmp/apptracer-web-live-device.log`. Flutter test refused integration Web devices;
Flutter drive with a local ChromeDriver was used instead.


Automatic iOS live verification passed after fixing an observed SDK callback handling
regression: OKTracer 1.5.2 reports noNeedToStart for omitted features (diskUsage,
systrace, metricKit, performance, otlp). Only that exact error path and recognized
unconfigured feature metadata are ignored for collection state; configured/unknown
start failures remain errors. Simulator logs show three ASSERT_REPORTER upload success
callbacks, but dashboard display is still unverified. Logs:
`/tmp/apptracer-ios-live-device.log`, `/tmp/apptracer-ios-live-native.log`.

The user's Web console screenshot contradicted the earlier expectation: only two
groups, no parsed stack, and DDC frame text included in the FormatException title.
The parser now understands the actual browser debug compiler trace and the HTTP
transport serializes symbolic frames in Tracer's supported V8 syntax. Raw traces
remain unchanged in the event model and diagnostic log. Web synthesizes issue keys
and skips runtime throw frames when choosing an application member. A new live browser
run passed and returned three HTTP 200 responses, with distinct StateError keys
`dart/StateError/<fn>` and `dart/StateError/build`. Correct console display was requested;
HTTP success is not treated as that proof. Log: `/tmp/apptracer-web-live-fixed.log`.


After the Web corrections, platform-interface VM tests passed (42 plus one browser-only
skip), the real browser stack fixture passed (one), HTTP tests passed (14), and facade
unit tests passed (78). Analysis of the affected packages passed. These checks prove
parsing/payload behavior and Dart regressions, not corrected dashboard rendering.

The first unrestricted Android release build reached compilation but failed because
GeneratedPluginRegistrant referenced the dev-only integration_test class excluded from
release. Concurrent device-test tooling on the same example had regenerated development
metadata during that build. Example builds/device tests are now serialized; the repeat
release build regenerates plugin files and is still running. No APK success is claimed
from the failed attempt.


The serialized obfuscated Android consent release build passed and produced
`build/app/outputs/flutter-apk/app-consent-release.apk` (16.8 MB), SHA256
`d8c068d38a972412042661488832f666c60e52e8017a3f3faa4f5431cd3ce31b`.
The APK manifest itself was extracted: both Tracer startup providers are absent,
the AndroidX startup provider remains, and four vendor initializer metadata entries
are retained. Extracted manifest/mapping/symbols are retained under the example build
outputs. Native Gradle `:apptracer_flutter_android:testDebugUnitTest` passed.

On Android API 35, the release app showed disabled at cold start, discarded an off
Dart probe, and enabled after explicit start; libtracernative.so loaded successfully.
Stop-and-clear returned restartRequired with Dart off. A cold emulator Ethernet pcap
was valid and contained zero packets. The enabled probe capture contained only one
packet, so server delivery is not established. The Play Store image rejects root and
run-as for release apps, so release diagnostic files have not been inspected. Debug
files/device-channel checks are the next separate acceptance step. Full native fatal,
ANR, offline/restart and server/dashboard gates remain open.

The iOS deferred device test passed again after the SDK callback fix and native
podspec version alignment (one executed test, one Android skip). Log:
`/tmp/apptracer-ios-consent-device-regression.log`. Web live verification also
passed in release mode through ChromeDriver, exercising dart2js rather than DDC.
That test checks client behavior; its release output does not establish upload
responses or dashboard rendering. Log: `/tmp/apptracer-web-live-release.log`.

Native podspec/Gradle versions and Sentry client metadata now match the prepared
`0.2.0-dev.1` release. All 23 Sentry tests passed after the metadata change.
No direct dependency or import of `meta` exists in the repository packages;
Flutter's transitive dependency remains outside their control.

## Follow-up device verification — 2026-10-02

The Android purge test now covers both SDK 1.4.0 storage roots: `cache/tracer`
and `files/tracer` (the latter contains the persisted device identifier). The
native unit suite passed with 22 tests. The device channel test passed, and a
separate debug-app run confirmed both roots were absent after stop-and-clear.
Cold-start checks still showed both roots empty before consent. This verifies
local deletion; it does not prove that a report already queued offline was
removed from every possible SDK or OS-owned store.

The consent APK was rebuilt after this cleanup fix with R8 and Dart obfuscation.
Its SHA256 is `c306a37e18d5302cdb19938fa3088b984fc5e5b7e1052cf0dd92ce9583c54bbe`.
The API 35 release run confirmed cold disabled state, explicit start, and
restart-required stop behavior. A JVM fatal probe produced Android exit reason
`APP CRASH(EXCEPTION)`; the next process again started disabled and required an
explicit start. An ANR probe also caused Android to log `ANR in
ru.apptracer.flutter.apptracer_flutter_example.consent`. The system ANR dialog
was not captured and no `REASON_ANR` process-exit/recovery report was confirmed,
so full native ANR reporting remains open. Release app-private files cannot be
inspected with `run-as` on this emulator; the two-root deletion result comes
from the debug device run.

With airplane mode enabled, SDK requests failed to connect and stop-and-clear
left the app disabled; after restoring connectivity the stopped process did
not resume collection. This does not prove whether every offline-queued report
was withheld from the server. Web debug and release browser live tests both
passed; DDC parsing and wire serialization were corrected. The Tracer console
view of the resulting groups/stacks has not been rechecked, so the screenshot
showing “Stacktrace not available” is not yet resolved by dashboard evidence.
The iOS simulator continues to return `native_cleanup_unavailable` while
keeping collection off; native purge and restart behavior remain unverified.

The iOS consent integration test was rerun on the iOS 18 simulator with the
farming project token: both test cases passed (one platform-specific skip).
It asserted that deferred start is refused twice with
`native_cleanup_unavailable`, Dart diagnostics remain discarded, stop returns
`native_stop_and_cleanup_unverified`, and collection stays off afterward.
The paired physical iPhone 16 Pro (iOS 26.7.1) is now connected by USB. Using
the FVM Flutter 3.47.4 build, its consent test passed (one iOS test, the
Android-only test skipped). The test verified deferred start is refused,
post-refusal Dart diagnostics stay unbuffered, and `stopAndClearCollection`
returns `native_stop_and_cleanup_unverified` while keeping collection off.
The earlier wireless-runner attempts were blocked by the wrong-architecture
`idevicesyslog`; the FVM SDK has a universal arm64/x86_64 binary.

The earlier physical live tests did not reach revocation: collection stayed off
and the network warm-up printed a DNS error. Those observations did not establish
that DNS caused the SDK startup failure. The DNS failure was subsequently traced
to the test invocation: Flutter 3.47.4 defaults to uninstalling integration-test
apps on exit. The app was confirmed absent after those runs; reinstalling it
caused iOS to request wireless-data permission again.

The separate `network_diagnostic_test.dart` initializes no SDK and uses no tokens.
With `--no-uninstall`, the app remained installed after the first diagnostic run.
After the user allowed wireless data, its next run resolved `sdk-api.apptracer.ru`
to two public addresses and received HTTP 404 over HTTPS: **one test passed**.
This proves DNS and HTTPS from the app process, not merely from Safari. A
subsequent live run retained the app, used the iOS project token, and no longer
reported the warm-up DNS failure. Collection still did not become enabled;
the native state explicitly returned `error / native_start_failed` from
`ios-native`. At that point SDK startup was a separate blocker; the physical release/profile runs below resolve it. The redacted live
log is `/tmp/apptracer-ios-live-retained.log`. Previous direct invocations also
passed the Android token as `TRACER_APP_TOKEN`; the example requires the iOS
token under that define, as its Makefile live target already specifies.
That debug run did not exercise active-start/revocation. Separately, the Dart client tests verify
that post-revocation events are discarded before crossing the platform
channel. Added an iOS platform regression test as well: after native
`stopAndClearCollection`, error, log, user ID, and custom-key calls do not
invoke the MethodChannel. All three iOS platform tests pass. This verifies the
Dart-to-native boundary; it does not inspect reports the native SDK may already
have queued or prove its native crash reporter stops recording after revocation.

An earlier Android device-channel attempt timed out while Gradle downloaded the
Flutter arm64 debug engine. That blocker was resolved by retrieving and verifying
the pinned engine artifacts; the later device-channel pass and purge checks are
recorded in the follow-up section above.


## Physical iOS acceptance — 2026-10-02, evening

Device: USB iPhone 16 Pro, iOS 26.7.1; Flutter 3.47.4; OKTracer 1.5.2.
The test app is kept installed. `flutter test` needs `--no-uninstall`;
`flutter drive` needs `--keep-app-running`. Reinstalling after the runner's
implicit uninstall resets wireless-data permission and caused the observed DNS
failures. The independent DNS/HTTPS test passed after permission was granted.

The separate `native_start_failed` was caused by the attached LLDB debugger:
SDK crashReporter reports `TracerService.isBeingDebugged`. Physical live tests
passed with `flutter drive --profile --keep-app-running`, without an attached
debugger. Use `TRACER_IOS_APP_TOKEN` as the example's `TRACER_APP_TOKEN` define.
The user supplied the iOS issue-list screenshot showing three expected groups:
build StateError, synchronous StateError and `[EXAMPLE-PARSE]`, each count 2.
This confirms delivery/group presence, not the detailed log/key contents.

### Uploader revocation regression

`example/integration_test/ios_collection_transport_test.dart` exercises the real
SDK against an HTTP server inside the phone. Nothing from these requests leaves
the device. A successful JSON response establishes working delivery, then a 503
establishes a failed upload. Before the fix, restoring success after stop caused
another request (count 2 -> 3). `service.stop()` alone was insufficient while
the plugin retained the service.

The plugin now also releases its service reference after stop. Both scenarios
passed on the physical phone: a failed request before stop, and a request whose
503 response is withheld until after stop (`TRACER_TEST_INFLIGHT=true`). No new
request started in the 35-second post-revocation window, a new Dart error was
ignored, and restart in that process was refused. Completing a request that
started before stop is distinct from starting a new request. This finite test
is not proof of on-disk purge or every possible background schedule.

Redacted logs: `/tmp/apptracer-ios-transport-release-service.log` and
`/tmp/apptracer-ios-transport-inflight.log`. The final in-flight run includes
`holdFailure=true` and a successful Xcode build; an earlier compile-failed run
that launched an old installed binary is excluded from evidence.

### Native crash after revocation — failed acceptance gate

The standalone release entrypoint `example/lib/ios_native_verification.dart`
selects scenarios through `APPTRACER_VERIFY_SCENARIO`. It writes non-secret
stage JSON under `Library/ApptracerVerification`, and uses loopback for both
native crash scenarios. With collection enabled, a fatal crash wrote a 95,625
byte `Library/Caches/ru.ok.tracer.crashreporter.data/<bundle>/live_report.okcrash`.
After `stopAndClearCollection`, collection was false, yet a native crash still
wrote a 95,614 byte report. This was reproduced with an independent Swift
`fatalError`, without calling the vendor crash trigger: 95,631 bytes. Stop plus
service release therefore does **not** uninstall the process-wide crash writer.

A new process in `deferred-recovery` completed with collection false and
`unsupported/native_cleanup_unavailable`. The saved crash retained its size
and modification time; SDK/log/session files were unchanged. Deferred mode
avoids constructing the service, but does not purge the saved crash.
A subsequent automatic start replayed the revoked report to the loopback test
server, with `OKTracer upload CRASH_REPORTER: ok`. Thus an automatic start in a
later process can upload a report captured after revocation. The revoked probes
were consumed by loopback; they were not deliberately replayed to the vendor.

This is a reproduced SDK limitation, not a passed consent guarantee. Keep
`native_cleanup_unavailable` and `native_stop_and_cleanup_unverified`; do not
advertise iOS consent support or enable deferred collection until native crash
capture and durable cleanup are implemented and tested. The SDK's public
service API has stop operations but no purge API, and its Objective-C crash
reporter header exposes enable and report-path operations without disable.
No private signal-handler reset or guessed directory deletion was introduced.

Regression checks: 10 Dart lifecycle tests and 3 iOS platform tests passed;
the release probe and transport test pass static analysis. No direct dependency
on `meta` or `package:meta` import was added to any package.


A subsequent enabled independent Swift fatal was recovered through the real
vendor endpoint in release without LLDB. At 22:49:54 Moscow time the native
callback confirmed `OKTracer upload CRASH_REPORTER: ok`, tag
`BCDDA2B7-9418-4B14-BB4A-DC5DD0E671A9`, attemptsCount 0, followed by queue drained.
Log: `/tmp/apptracer-recovery-console.log`. This confirms server acceptance of
the enabled native crash; symbolication/dashboard contents require the report
view and are not inferred from the upload callback.

The user then supplied the log/data screenshots captured at 22:54. The selected
event is explicitly **iOS 18.0 simulator**, crash time **12:29:06**, displayed
event time **12:29:08** on 2026-10-02. They confirm the earlier simulator report:
two `ui` breadcrumbs with `screen=home`, the verbatim FormatException Dart stack
with source locations and async frames, `checkout_step=3`, `endpoint=/orders`,
`dart.exception_type=FormatException`, and `issueKey=EXAMPLE-PARSE`. This closes
log/custom-key rendering for that simulator event. It does not establish the
contents of the evening physical-device report, native symbolication, or consent
revocation. The earlier issue-list screenshot alone cannot identify which
devices contributed its counts.

The subsequent user-supplied log/data text confirms the physical-device event
at **22:19:25 on 2026-10-02**, model **iphone_16_pro**, OS **26.7.1**, app 1.0.0.
Both `ui` breadcrumbs (`screen=home`) are present, followed by the verbatim
FormatException stack: frames 0–33, source files/lines including `main.dart:241`,
and async suspension markers. Custom data includes `checkout_step=3`,
`endpoint=/orders`, `dart.exception_type=FormatException`,
`issueKey=EXAMPLE-PARSE`, and the expected exception message. This closes
physical-device Dart report delivery, log-stack rendering, breadcrumbs and
custom-key rendering for that run. It does not close native crash symbolication
or the reproduced native revocation failure.


## iOS revocation remediation — 2026-10-02, late evening

The earlier failure is addressed in the plugin, without changing SDK signal
handlers. CocoaPods and SPM pin **OKTracer exactly 1.5.2** because the adapter
uses its audited storage layout. Review the layout and repeat device acceptance
before changing that version.

- Deferred bootstrap constructs no service. An explicit deferred start prepares
  storage before constructing OKTracer. Previous reports are discarded by default;
  `preservePreviousReports=true` is for the same authorized account only.
- Stop marks `Library/Application Support/apptracer_flutter/collection-revoked`
  before stopping the service, detaches the service/delegate, clears Dart logs,
  and removes SDK report directories. Empty files replace `Library/TracerStorage`
  and `Library/Caches/ru.ok.tracer.crashreporter.data/<bundleID>`. They prevent the
  surviving crash writer from recreating queued reports. The process-wide handler
  is not uninstalled. Existing open file descriptors cannot restore unlinked files.
- SDK task metadata (`ru.ok.tracer.crashes` preferences domain,
  `ru.ok.tracer.uploadtasks`) and its cached system info are cleared at stop and
  again before a purge/start. Host preferences and unrelated paths are retained.
- After an active session, stop returns `restartRequired`. No second service can
  start in that process. Stopping before any native start returns `disabled` and
  still seals old report storage.
- In a new process, automatic startup returns `disabled/consent_required` when
  the durable marker exists. Explicit deferred start after new consent purges
  old storage even if `preservePreviousReports=true`, then opens fresh directories.
  Purge failure or a symlink in the storage path returns `native_cleanup_failed`
  and does not create an SDK service. Applications still own their consent state;
  the marker is a revocation safeguard, not a grant of consent.
- Requests already started before revocation may finish. New reports and retries
  are blocked; already delivered server data is unaffected.

The physical release probe reproduced Swift fatal-after-stop with this adapter:
only the two empty guard files and revocation marker remained, no crash report.
A later automatic recovery was refused with `consent_required`; a new explicitly
consented session received zero old reports during its 20-second loopback window.
The standalone Swift storage tests cover pending-report purge, blocked writes,
marker persistence across instances, re-consent, unsafe symlink failure, and
preservation of unrelated files. Additional final transport runs are recorded below.


An immediate start/stop regression exposed an OKTracer `unowned` reference
crash if the stopped service is deallocated while startup work is pending.
The final adapter retains one terminal stopped service until process exit,
without its delegate and without exposing it to new event calls. Sealing the
storage removes the payloads its retry tasks would read. Repeated stop retains
that same terminal object. This supersedes the earlier release-only mitigation;
the service's memory is not claimed to be fully erased before process exit.


Final retained-service profile tests on the physical iPhone passed:
`/tmp/apptracer-sealed-retained-offline.log` and
`/tmp/apptracer-sealed-retained-inflight.log` each confirm no new HTTP request
in the 35-second post-stop window. `/tmp/apptracer-sealed-retained-lifecycle.log`
passes deferred bootstrap, cold stop, explicit start, immediate active stop,
repeated stop and refusal to restart, with a five-second post-stop survival
check. This resolves the unowned-reference crash from the release-only attempt.
The 3 iOS platform tests, 10 Dart lifecycle tests and host storage checks passed.
The tested arm64 OKTracer binary SHA-256 is
`379dabc5c483035df4253d2c42edf8e23a56a405f70ab94b0996aadb57b709de`.


The final release `new-consent` probe completed at 23:28:48 on the physical
phone. It explicitly requested `preservePreviousReports=true`, observed zero
old requests for 20 seconds, then submitted one fresh error and received exactly
one loopback upload. It stopped successfully with `restartRequired` afterward.
The SDK confirmed the fresh ASSERT_REPORTER upload; old offline data was not
replayed. Evidence: `/tmp/apptracer-final-new-consent.json` and
`/tmp/apptracer-final-new-consent-console.log`.


Final release native-after-revoke probe at 23:29:55 had collection false,
`restartRequired`, and zero loopback requests. Container assertions after the
Swift fatal found the durable marker and both zero-byte guard files, with no
`live_report.okcrash`. The next automatic launch returned `consent_required`;
the next deferred bootstrap completed disabled with the same reason and no SDK
startup logs. Files: `/tmp/apptracer-final-native-revoked.json`,
`/tmp/apptracer-final-native-files.json`, `/tmp/apptracer-final-blocked-auto.json`,
`/tmp/apptracer-final-deferred.json`. The standard macOS check script now runs
`tool/check_ios_storage.sh` as well.


The final enabled native crash recovered successfully through the actual vendor
endpoint at 23:32:19: `OKTracer upload CRASH_REPORTER: ok`, tag
`6CD011A8-4F1D-4912-AAA9-20D177F90E7F`, attemptsCount 0, followed by queue drained.
This verifies authorized native recovery remains functional with the final
adapter. Log: `/tmp/apptracer-final-native-delivery-console.log`. Dashboard
native symbolication is not inferred from that callback. The iOS revocation
regression is closed for these tested 1.5.2 scenarios; full cross-platform
release gates described at the top remain separate.


### Additional physical iOS lifecycle checks — 2026-10-02, 23:46–23:51

The release probe passed on the same iPhone 16 Pro:

- `multi-engine`: a second engine sees the active service. After revocation,
  two subsequently created/destroyed engines see `restartRequired`, refuse
  initialization and cannot send logs. Three secondary engines, zero requests.
- `cleanup-failure`: replacing only the known empty SDK guard with a test symlink
  produces sticky `error/native_cleanup_failed`. Repeated start stays off,
  unrelated sentinel survives, zero requests. The probe restores the guard.
- `missing-token`: explicit start returns `error/app_token_missing`, stays off
  and produces zero requests.

Results: `/tmp/apptracer-multi-engine.json`,
`/tmp/apptracer-cleanup-failure.json`, `/tmp/apptracer-missing-token.json`.
These scenarios live in `example/lib/ios_native_verification.dart`; they use
loopback and do not send synthetic diagnostic payloads to the vendor.


Account separation also passed on the physical release build: `account-a`
created an error with a synthetic user ID, key and breadcrumb; loopback returned
503. After revocation, no retry occurred. In a new process `account-b` requested
preservation of previous reports, but the prior revoke forced purge. There were
zero requests for 20 seconds, followed by exactly one fresh account-B report.
Decoded multipart payloads contain six A markers and no B markers in A's request,
and six B markers with **zero A markers** in B's request. Thus the old user ID,
custom key, breadcrumb and error text were not carried into the new event.
Both sessions finished stopped (`restartRequired`). Captures are local-only in
`/tmp/apptracer-account-capture` and must not be published (SDK request bodies).


### iOS verification completed — 2026-10-03

The user confirmed native source-level symbolication for Runner and Flutter in
incident `74895A7E-E5DB-4822-802B-5DC2E4B2F8E6` (`AppDelegate.swift:75:11`).
The tested iOS delivery, revocation, restart/re-consent, account separation and
failure cases are complete for OKTracer 1.5.2. See the reproducible Xcode 27
DWARF-4 setup in [symbolication.md](symbolication.md). This closes the iOS
follow-up, not the full Android/Web/release checklist. The app remains installed
with collection off; no publication or downstream app migration was performed.


### Android release/R8 follow-up — 2026-10-03

The automated `android_native_verification.dart` entrypoint runs against the
actual SDK 1.4.0 on the API-35 arm64 emulator. Release APK, R8 and Dart obfuscation
are enabled; both automatic Tracer providers are absent, all four SDK initializer
metadata entries remain, and `libtracernative.so` loads. Test-only loopback routing
and cleartext permission apply to the consent verification flavor.

Passed so far (JSON records `/tmp/apptracer-android-<scenario>.json`):

- Clean-install `cold`: disabled, no SDK files, no requests for 10 seconds.
- `offline`: both session and actual `/api/crash/upload` requests receive 503;
  revoke deletes both SDK roots. Restoring successful responses produces no new
  requests for 35 seconds. An earlier probe watched session requests only; the
  corrected harness explicitly waits for `/api/crash/upload`.
- `inflight`: responses are held until after revoke begins, then released.
  Stop drains current work, clears storage, returns `restartRequired`, and no
  additional request occurs in the next 35 seconds.
- `account-a` to `account-b`: after a failed account-A upload and purge, a new
  process with `preservePreviousReports=true` produces no old crash request for
  20 seconds and then delivers a fresh account-B report. Decoded multipart
  bodies contain six A markers only in A and six B markers only in B; no cross-
  account user ID, custom key, breadcrumb or message survives.
- `multi-engine`: three additional engines share the service/terminal state;
  initialization after stop is refused, no new requests, no diagnostic files.
- `activity`: Activity/engine recreation after stop returns `restartRequired`,
  stays off, has no diagnostic files and no requests.
- `native-revoked`: OS records native SIGSEGV (exit reason 5); next idle process
  sees no SDK files. Explicit new consent with preservation requested produces
  only a fresh session request, no crash upload, and stops cleanly.

A real ANR after revocation was terminated through the system's Close app action;
`ApplicationExitInfo` records reason 6 with a trace. SDK bytecode examines old ANRs
when no session timestamp exists, but `AnrReporter.report` skips them when purge
removed `prevLaunchSystemState`. No old crash upload was observed in subsequent
consented starts. This distinction matters: deleting SDK files does not delete
Android's system exit history.


Further Android results, 00:37–00:51:

- Authorized SIGSEGV writes a 1,161,840-byte minidump; the next deferred start
  with preservation enabled converts it to a MINIDUMP report and runs against
  the real Tracer endpoint. JVM fatal similarly writes stacktrace/system/log
  files and enters recovery. The user subsequently confirmed both in Tracer.
- JVM fatal after revoke produces no SDK files. A new preserved session sends
  only trackSession, with no crash upload and no post-stop requests for 35s.
- Authorized ANR: system Close app action records reason 6, PID 18902 at
  00:48:11; recovery builds a 45,125-byte ANR stack. The user supplied the Tracer
  report: main thread sleeping in MainActivity.configureFlutterEngine, with
  readable class/method names after R8. Delivery and ANR recovery are confirmed.
- Injected initial purge failure (0500 permissions on the SDK directory) rejects
  two starts, stays off, sends nothing and preserves an unrelated sentinel.
- Injected stop purge failure returns error, prevents restart and sends no new
  requests for 35s. Restoring fixture permissions allows final cleanup; roots
  are empty. The harness restores permissions in finally in both probes.


The repeated revoked ANR probe also passed with the corrected request predicate:
PID 19558, OS reason 6 at 00:52:05, then preserved new consent at 00:52:06.
Only trackSession was requested; no crash upload, no files after final stop and
no new requests for 35s. The positive control above demonstrates that this SDK
and emulator can capture/upload ANRs while collection is authorized.


Android missing-dependency release probes passed:

- No vendor SDK: R8 initially found an absent javax.inject.Provider referenced
  by the consent wrapper's SDK configuration. A narrow consumer dontwarn rule
  fixes the optional dependency build; actual API-35 launch returns
  unsupported/sdk_missing, no files and no requests. APK size 14.2 MB.
- Empty generated tracer_app_token: the release probe returns
  error/app_token_missing, remains off, no files and no requests. The temporary
  resource-generation fixture was removed, and the normal token resource was
  verified restored after rebuilding. A flavor XML alone did not override the
  plugin-generated variant resource, so that earlier attempt was not evidence.
- Latest SDK-enabled APK before the final style-only harness edit:
  SHA256 820e16f190baf9a77df96a18c7d9676fdc4dc830ea9bfd479e52b6efadae6aed.
  Both Tracer startup providers absent; logger/core/crash/native metadata
  retained. The normal consent app was restored and stopped after a fresh Dart
  report probe. Direct meta dependency/import scan found none.

### Web lifecycle and release source-map follow-up — 2026-10-03

Fixed the HTTP transport's closed-client reuse and retained account data. Stop
now clears logs/keys/user ID, ignores off-state diagnostics and recreates an
owned client on the next start. An injected client remains caller-owned;
requests already in flight can complete. VM and Chrome regression tests pass.

Release live verification includes explicit restart, a fresh
web-consent-restarted report and final stop. The user confirmed delivery and
partial source-map rendering. Its anonymous application frame was incorrectly
encoded as a member plus null:0:0. The local map has a valid entry for generated
69562:54 (integration_test/live_verification_test.dart:144:20), proving that the
coordinates were lost before source-map lookup. Fixed anonymous V8 frame parsing
and added parser plus serialized-payload regressions. The user then confirmed
the corrected anonymous frame as
`../../../integration_test/live_verification_test.dart:147:23` and
`main.<anonymous function>`. This closes the lost-location regression. The
console reports line 147 while `StackTrace.current` is on source line 144;
exact line/column fidelity is not established by this result. Some optimized
SDK frames still retain generated JS coordinates.


Corrected release probe at approximately 01:06: source-map upload accepted before
running the live test. JS SHA256
54c6fd4954b58e6754ab295977994f40a342ce923f33c7a3319b3c6e05e2d452,
map SHA256 97aa15da00083056b954b99f371ffa3764b0a605e5d8035ef468aa635e1a239c;
both hashes match the subsequent flutter drive build. The parser regression and
12 HTTP payload/lifecycle tests pass in Chrome. Collection finishes disabled.


Final automated checks: 175 package/example tests, 12 additional HTTP Chrome
cases, 22 Gradle native unit tests, standalone JVM executor and Swift storage
checks passed. Format/analyze clean in all seven packages and the example.
Publish dry-run returns nonzero because tracked files are modified; local path
overrides are also flagged as hints. This is no claim of dependency resolution
against unpublished prerelease packages. No package publication was attempted.
The check script now propagates get/format/analyze failures explicitly rather
than masking them with the exit status of a later test.

Final release/R8 APK rebuilt after all Dart changes: SHA256 367fd6084e5d6d66ffece555dd01f179296f03c37c49014d169f517598ba6048.

### Final dashboard confirmation — 2026-10-03

The user supplied the authorized Android SIGSEGV report and the JVM fatal
`IllegalStateException: Native consent JVM fatal probe`, with
`MainActivity.configureFlutterEngine` and the SDK/adapter uncaught-handler chain.
Together with the earlier ANR, iOS and corrected Web reports, this completes
the tested collection/revocation acceptance. Final Android cold launch is
disabled, with no SDK files or requests; iOS is also left stopped.

Native symbolication is explicitly partial: the report lists base.apk,
base.odex and base.vdex with zero identifiers, plus libtracernative.so with
module ID D5B64C068B0886E64ECCE961A798300F0. Running the vendor dump_syms on the
actual arm64 library produces the same ID, 26 PUBLIC and 5460 STACK records,
but no FUNC records. It does not provide full function/source symbols.
The zero-ID/APK mapping limitation was investigated separately in
[symbolication.md](symbolication.md); this receipt confirms delivery, not full
native frame decoding. No modification to vendor binaries or fabricated symbols
is part of the consent adapter. Package publication and downstream migration
remain separate from this completed verification.
