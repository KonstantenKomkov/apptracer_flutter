# Platform matrix

Everything below was verified against the live artefacts on the dates shown, not
copied from prose documentation. Where a fact could not be verified it says so.

Last verified: 2026-08-25.

## Summary

| Platform | Backend | Dart errors | Native crashes | ANR / hangs | Crash-free | Status |
|---|---|---|---|---|---|---|
| Android | `ru.ok.tracer` SDK via method channel | yes | yes, by the native SDK | yes, by the native SDK, **Android 11+ only** | yes, by the native SDK | implemented |
| iOS | `OKTracer` SDK via method channel | yes | yes, by the native SDK | hang count, by the native SDK | via native sessions | implemented |
| Web | Tracer's own HTTP ingest, pure Dart | yes | n/a | n/a | no | verified against a live project 2026-08-26; breadcrumbs, custom keys and `userId` added and verified 2026-08-27 |
| macOS / Windows / Linux | Tracer's own HTTP ingest, registered by hand | yes | no | no | no | **not supported in this release** — never run |
| Aurora OS | the same, registered by hand | yes | no (needs the vendor's C/C++ SDK and system minidumps) | no | no | **not supported in this release** — never run |

"Implemented" means the code exists, analyses clean and is unit-tested. See
[status.md](status.md) for what has and has not been exercised against a real
Tracer project.

**Aurora is a C/C++ project, not a Sentry one.** The vendor ships a native
`libtracernative.so`, a C++ header and Python upload scripts; integration is
`tracer_init(app_key, storage_dir)`, and crashes arrive as minidumps collected
by the system `crash-dumper`. Read from the vendor's Aurora documentation on
2026-08-26. A Flutter application cannot produce those minidumps from Dart, but
Dart errors can still travel over the same HTTP ingest the web path uses.

**ANR needs Android 11.** `AnrReporter.collect` in `tracer-crash-report` 1.4.0
opens with `if (Build.VERSION.SDK_INT < 30) return emptyList()` and then reads
`ActivityManager.getHistoricalProcessExitReasons`, filtering on `REASON_ANR`
(6). Below API 30 no ANR is ever reported, whatever
`CrashReportConfiguration.setSendAnr(true)` says; `AnrWatchdogThread` still runs
and stores thread snapshots, but those only enrich a report that will not be
created. Read from the bytecode of the published AAR, and confirmed on a live
Android 10 device on 2026-08-26: the system raised an ANR, and the SDK reported
`No crashes detected` on the next start.

The report also depends on the system killing the process **while the main
thread is still stuck** — that is what `REASON_ANR` records. A block that ends
on its own leaves a healthy process and produces nothing, however loudly the
ANR dialog complained.

## Android

| Item | Value | How it was checked |
|---|---|---|
| Runtime artefacts | `ru.ok.tracer:tracer-platform` (BOM), `tracer-crash-report`, `tracer-crash-report-native`, `tracer-heap-dumps`, `tracer-disk-usage`, `tracer-profiler-sampling`, `tracer-profiler-systrace` | Maven Central |
| Latest version | `1.4.0` | `repo1.maven.org/.../tracer-platform/maven-metadata.xml` |
| Gradle plugin | `id("ru.ok.tracer") version "1.4.0"`, resolved from **Maven Central**, not the Gradle Plugin Portal | plugin portal returns nothing for the marker artefact |
| `minSdkVersion` | **21** | `AndroidManifest.xml` inside `tracer-commons-1.4.0.aar` |
| Permissions added | `INTERNET`, `ACCESS_NETWORK_STATE` | same manifest |
| Initialisation | automatic, through `ru.ok.tracer.startup.InitializationProvider` (a content provider) plus `TracerInitializer` | same manifest |
| Configuration | `Application` implementing `ru.ok.tracer.HasTracerConfiguration`, or `Tracer.runtimeConfigs` seeded before `Tracer.init` runs | `javap` on `tracer-commons` |
| Generated resources | `tracer_app_token`, `tracer_environment`, `tracer_is_disabled`, `tracer_mapping_uuid` | bytecode of `ru.ok.tracer.mapping_plugin.TracerUploadMappingPlugin` |
| Log buffer | circular, **65536 bytes** by default (`maxLogsLength`), oldest entries evicted first | default value read from `CrashReportConfiguration` bytecode |
| License | Tracer's License Agreement, <https://apptracer.ru/license/> | `<licenses>` in `tracer-crash-report-1.4.0.pom` |

### Why 1.4.0 is the floor

Not arbitrary. The vendor's own release notes make the older versions a bad
bet, and two of the fixes land squarely on this package:

* **1.3.3** — native symbol collection and upload started working on Apple
  Silicon Macs, and a warning with Groovy build scripts was fixed. Both matter
  here: the symbol experiment below runs `dump_syms` locally (the binary
  shipped in `tracer-plugin-1.4.0.jar` is a universal `x86_64 + arm64` Mach-O,
  verified with `lipo`), and the example applies the Tracer plugin from a
  Groovy `tracer.gradle` so that it can be conditional.
* **1.4.0** — log initialisation no longer crashes on a full or corrupted
  store, and very long stack traces no longer crash the SDK. A Flutter app
  forwarding Dart traces is exactly the workload that produces long ones.
  1.4.0 also began reporting remaining storage space with each crash, and
  added `UserSampleUpload.attachment()` for attaching a file to a non-fatal.

### Three things that look like tags but are not

Easy to conflate, especially now that the Tracer UI has its own tags:

| Thing | Set by | Where it shows |
|---|---|---|
| `Tracer.setCustomProperty` — what `setCustomKey` maps to | this package | event → "Данные" |
| `Tracer.setKey` — value capped at 31 characters | not used by this package; **this is what `tracer_set_key` from the JNI bindings maps to** | event → "Ключи" |
| `issueKey` | this package, per event | event title; overrides grouping |
| UI tags, assignees | a human, in the Tracer web interface | issue list |

Only the first three come from code. The UI tags are applied to issues by people
and are not settable from an SDK.

### If your app also builds its own native code

Not the common case for Flutter — `libflutter.so` and `libapp.so` are prebuilt
by the engine, and the vendor's own guidance is that the JNI bindings are
unnecessary unless you compile C/C++ yourself. An application with a `dart:ffi`
plugin that builds native sources is the exception, and there the vendor's
[JNI bindings](https://apptracer.ru/doc/android/jni-bindings/) let that code
call `tracer_log` and `tracer_set_key` directly. Two interactions with this
package are worth knowing:

* `tracer_log` resolves to `TracerCrashReport.log`, the **same 64 KiB circular
  buffer** this package writes breadcrumbs and verbatim stack traces into. A
  chatty native logger and a chatty Dart one compete for the same space; that is
  what `TracerOptions.maxRawStackTraceLogBytes` is budgeting against.
* `tracer_set_key` resolves to `Tracer.setKey`, not `setCustomProperty`. Keys
  written from native therefore land in the "Ключи" tab while
  `Tracer.setCustomKey` from Dart lands in "Данные". Mixing both is fine, but
  they will not appear side by side.

The API this package uses:

```
ru.ok.tracer.Tracer.setCustomProperty(String, String)      // "Данные" tab, value ≤ 128 chars
ru.ok.tracer.Tracer.setKey(String, String)                 // "Ключи" tab, value ≤ 31 chars
ru.ok.tracer.Tracer.setUserId(String)
ru.ok.tracer.Tracer.disable()
ru.ok.tracer.Tracer.isDisabled()
ru.ok.tracer.crash.report.TracerCrashReport.report(Severity, Throwable, String issueKey)
ru.ok.tracer.crash.report.TracerCrashReport.log(String)
```

`setCustomKey` maps onto `setCustomProperty` rather than `setKey`, because a
31-character value limit is too small for most of what callers want to attach.

### Two options that cannot come from Dart

Both `TracerOptions.appToken` and `TracerOptions.environment` are **ignored on
Android**, and the plugin logs a warning for each rather than pretending they
took effect.

* `appToken` — see below.
* `environment` — the SDK reads it from the Gradle plugin, which defaults it to
  the build variant name. Set it in the `tracer { }` block, or override it with
  `CoreTracerConfiguration.setOverrideEnvironment` from an `Application`
  implementing `HasTracerConfiguration`.

### The appToken cannot come from Dart

`TracerOptions.appToken` is **ignored on Android**. The SDK reads its token from
the `tracer_app_token` string resource that the Gradle plugin generates at build
time. The only documented runtime override is
`CoreTracerConfiguration.Builder.setOverrideAppToken`, and it lives in the
configuration the SDK settles at start-up — from an `Application` implementing
`HasTracerConfiguration`, or from the seam `TracerAutoConfig` uses before
`Tracer.init`. Both happen inside a content provider, before
`Application.onCreate` and long before Dart runs; replacing that map afterwards
would discard whatever configuration the application put there. The plugin logs
a warning when a token is passed anyway, rather than pretending it took
effect.

### Limits, with their actual values

Read from `ru.ok.tracer.crash.report.BuildConfig` in the 1.4.0 AAR, because
several of them are either undocumented or documented differently:

| Constant | Value | What it means here |
|---|---|---|
| `LIMIT_MAX_NON_FATALS_PER_SESSION` | 8 | the **hard** cap. Every Dart error this package reports is a NON_FATAL, so this is the ceiling per session unless the rate limit below is switched on |
| `LIMIT_MAX_NON_FATALS_PER_INTERVAL` / `_INTERVAL_MS` | 10 per 3 600 000 ms | the softer rate limit enabled by `setExperimentalNonFatalRateLimitEnabled(true)`, which the vendor recommends turning on |
| `LIMIT_MAX_ISSUE_KEY_LENGTH` | 32 | see the iOS section above |
| `LIMIT_MAX_LOGS_LENGTH` | 65536 | the circular log buffer |
| `LIMIT_MAX_CRASH_REPORTS_STORED` | 10 | undelivered crashes held on the device |
| `LIMIT_MAX_CRASH_REPORT_TTL_MILLIS` | 14 400 000 (**4 hours**) | undelivered crashes older than this are discarded. The documentation says "4000 часов", which is off by a factor of 1000 |

Two of these are worth acting on. The vendor's own recommendation to enable
`setExperimentalNonFatalRateLimitEnabled` is worth following — a healthy
application will not produce eight Dart errors in a session, but the failure
mode when it does is silent. And the 4-hour TTL means a device that is offline
for an evening loses its crashes; that is the vendor's behaviour, not something
this package can change, but it explains missing reports.

There is also a service-wide limit of **1 000 000 events per day**.

### Build-level switches worth knowing

From the Gradle plugin's configuration, all confirmed against the plugin
bytecode:

* **`dontFailOnUploadFailure` defaults to `false`** — a failed mapping upload
  fails the build. That is the right default and this package does not change
  it. Mappings are also staged in `build/tracer`, so a failed upload can be
  retried after the fact — but read the timing rule in
  [symbolication.md](symbolication.md) first: mappings apply only to events
  received after the upload, and there is no re-symbolication, so a late upload
  does not rescue crashes already collected.
* **`forceUploadNativeSymbols`** does two things, in this order: it keeps
  libraries the plugin graded as unusable (`quality != FULL`) in the upload
  list, and it skips the `nativesymbol/exists` check. Left **off** here,
  including for the Dart symbol upload, which needs neither; see
  [symbolication.md](symbolication.md).
* **`additionalLibrariesPath`** carries Dart AOT symbols into the native-symbol
  channel, and the upload works — but as of 2026-08-27 nothing is ever matched
  against them, because the SDK records `libapp.so` with a zero build id. Same
  document, finding 2.
* **`isDisabled`** switches the SDK off for a build variant entirely. This
  package handles it gracefully: `Tracer.isDisabled` is checked at startup and
  the integration reports "collection is off" rather than failing.

### stopCollection is one-way

`Tracer.disable()` sets a private `volatile boolean isDisabled` and there is no
re-enabling method (verified in the bytecode of `tracer-commons-1.4.0`). Calling
`Tracer.stopCollection()` therefore stops native collection for the remainder of
the process. The Dart-side handlers *are* restored and a later `initialize` does
restart Dart-side reporting, but native crashes stay off until the app restarts.
To never start in the first place, use `TracerOptions.isCollectionEnabled`.

## iOS

| Item | Value | How it was checked |
|---|---|---|
| Pod | `OKTracer` | `github.com/odnoklassniki/tracer-ios`, `Specs/OKTracer/*` |
| Spec repository | `https://github.com/odnoklassniki/tracer-ios.git` — a custom source that the host `Podfile` must declare | podspec layout |
| Latest version | `1.5.2` — and the **floor** this package declares, see below | `Specs/OKTracer/` listing |
| Distribution | binary `OKTracer.xcframework` downloaded from `nexus-external.vkteam.ru`, plus an `OKTracer.bundle` holding a root CA certificate | podspec `:http` source, zip listing |
| Architectures | `ios-arm64`, `ios-arm64_x86_64-simulator`, `tvos-arm64`, `tvos-arm64_x86_64-simulator` | `Info.plist` of the xcframework |
| Deployment target | iOS **12.4** for the binary; this package declares **13.0** to match Flutter | `-target arm64-apple-ios12.4` in the `.swiftinterface` |
| Required linker flag | `-weak-lswiftDemangle` | podspec `xcconfig`; also needed for SPM |
| Linkage | the xcframework is **static**, so the host `Podfile` needs `use_frameworks! :linkage => :static` | `pod install` fails otherwise with "transitive dependencies that include statically linked binaries"; reproduced and fixed in the example |
| License | "Tracer's License Agreement"; the repository `LICENSE` file is one line pointing at <https://apptracer.ru/license> | repository |

### Why 1.5.2 is the floor

Not a feature threshold. On 2026-08-31 the vendor moved its binaries from
`artifactory-external.vkpartner.ru` to `nexus-external.vkteam.ru` and took the
old host down; the announcement of 1.5.2 (2026-09-02) says it differs from
1.5.1 only in the version number and the host. Every podspec in
`Specs/OKTracer/` up to 1.5.1, and the `Package.swift` at every tag up to
1.5.1, still point at the old host — checked 2026-09-02: the 1.5.1 archive
answers `404`, the 1.5.2 archives `200`. A floor of 1.4.0 would therefore
promise three versions that cannot be installed. A `Podfile.lock` that pins
1.5.1 still has to be moved by hand — `pod update OKTracer`, since `pod
install` keeps a locked pod even with `--repo-update` — but with the floor it
stops at a resolver message naming the constraint rather than at a 404 from
the download.

The API this package uses, taken from the shipped `arm64-apple-ios.swiftinterface`:

```swift
TracerFactory.tracerService(configuration:items:delegate:) -> TracerServiceProtocol
Configuration.init(_ endpointConfig:features:sysInfoProvider:logProvider:logDestinations:)
EndpointConfiguration.init(token:url:)
TracerNonFatalModel.init(message:traceType:tags:properties:fileName:function:line:issueKey:severity:)
TraceType.custom(callStackAddresses:threadName:callStackSymbols:dropFirstSymbols:)
TracerServiceProtocol.send(nonFatal:) / update(properties:) / update(tags:)
TracerServiceProtocol.setUserId(_:) / setEnvironment(_:) / stop()
TracerLogProviderProtocol.getData() / getData(event:)
```

### How Tracer groups events

Worth knowing, because it constrains both platform implementations.

`crashId` — the grouping identity — is computed from the event's title and
subtitle, which come from the error name or are derived from the stack trace.
**File names and line numbers are excluded on purpose**, so that a code edit
does not split an existing group. For non-fatals, a supplied `issueKey` takes
over as the grouping parameter outright.

Two consequences this package depends on:

* **On Android**, grouping falls out of the injected `StackTraceElement` array.
  Since file and line are ignored, what actually drives it is
  `declaringClass` + `methodName` — which is why the Dart member is split
  across those two fields and the Dart URI goes in `fileName`. Reports stay
  grouped when the code moves.
* **On iOS**, the synthesised `issueKey` below is the grouping key, so it must
  not contain anything that changes when code moves.

`crashId` is computed **after** mappings are applied, so the same failure
arriving symbolicated and unsymbolicated lands in two different groups. That
matters for any build with `--split-debug-info`, obfuscated or not; see
[symbolication.md](symbolication.md).

### Grouping needs an explicit issueKey

A Dart stack trace has no native call-stack addresses. Tracer's own
documentation states that a supplied `callStackSymbols` array is **ignored
unless a debugger is attached**, so in a release build there is nothing left to
group on and every Dart error in the app would collapse into a single issue.

The iOS implementation therefore synthesises an `issueKey` from the Dart error
type and the innermost named frame when the caller did not supply one:

```
dart/<ExceptionType>/<member>
```

The key is bounded to **32 characters**. `LIMIT_MAX_ISSUE_KEY_LENGTH = 32` is
declared in the Android SDK's `BuildConfig`; whether it truncates or rejects
could not be established from the bytecode, and the iOS SDK publishes no
equivalent. But an unbounded key runs to 37–56 characters in ordinary cases, so
if truncation does happen it happens on nearly every event — and two errors
sharing a 32-character prefix would then merge into one group, which is worse
than not grouping. When the key does not fit, it becomes the tail of the member
plus a digest of the full identity, so trimmed keys cannot collide:

```
dart/_TypeError/Repository.load     (fits, used as-is)
d/MyHomePage.build#421e86           (trimmed, digest keeps it distinct)
```

Neither the file nor the line number is in it, and that is the whole point.
Tracer computes `crashId` from a title and subtitle and **explicitly ignores
file names and line numbers**, so that editing a file does not scatter one
issue across several groups. An `issueKey` is used verbatim instead, so putting
a line number in it would reintroduce exactly the instability Tracer went out of
its way to avoid: every release that shifted the code by a line would open a
fresh group. A function name is stable across edits inside that function, which
is the right granularity.

Pass your own `issueKey` to `Tracer.recordError` to override it.

### Breadcrumbs

Delivered through `TracerLogProviderProtocol`, not through the SDK's own file
log destination. Using the provider keeps Tracer's internal logging verbosity
untouched, so enabling breadcrumbs does not also enable a flood of SDK
diagnostics in the attached log.

### There is no remove-key operation

`TracerServiceProtocol` exposes `update(properties:)` and `update(tags:)` but no
delete. `Tracer.removeCustomKey` therefore writes an empty value on iOS, which
shows the key as deliberately cleared rather than leaving a stale value.

## Web

Tracer ships a JavaScript SDK as the npm package `@apptracer/sdk`
(latest `2.6.9`, ISC licensed — verified against the npm registry). A Flutter
web build has no way to bundle an npm package, so the web implementation speaks
the same HTTP ingest that SDK speaks, from pure Dart:
`POST /api/crash/uploadBatch` authenticated by the project's `appToken`. The
wire format was recovered from a captured request on 2026-08-26 and is written
down in [web-protocol.md](web-protocol.md).

Consequences worth knowing:

* Only Dart errors are captured. A failure inside an unrelated third-party
  `<script>` is invisible to this package.
* Frames are `dart2js` frames. Tracer matches source maps **by file path, not by
  Debug ID** as Sentry does, so the paths inside an uploaded source-map archive
  must match the paths in the frames. See [symbolication.md](symbolication.md).
* `TracerOptions.appToken` is required. `dsn` is not used by any path: Tracer
  issues no DSN to any project.
* Breadcrumbs, custom keys and `userId` do travel — since 2026-08-27, and not
  before it: those four methods used to be empty on this transport. Custom keys
  are sent twice, once where the console reads them and once where the vendor's
  own SDK puts them; see [web-protocol.md](web-protocol.md).
* A `200 {"success":true}` is not proof the payload was understood. The ingest
  answers that to a body that is not JSON at all; only a bad token is refused.
  There is no way to fail closed on a malformed event, only on a bad token.
* No crash-free metric: `POST /api/crash/trackSession` is a separate module in
  the vendor's SDK and this package does not report sessions.

## Desktop and Aurora OS

**Not supported in this release** — a decision taken 2026-08-27, not an
oversight. Neither platform has a Flutter-facing Tracer SDK, and neither has
been run against a real project even once, so nothing here is a promise. The
transport below exists because web uses it; registering it on a desktop build
would probably deliver Dart errors, and "probably" is the whole claim.

* **Aurora OS.** Tracer publishes a C/C++ SDK (`tracer.h` plus
  `libtracernative.so`, current version 0.1.15) that relies on the system
  `crash-dumper` package for minidumps. Binding it would mean shipping an
  Aurora-specific Flutter embedder plugin, which is out of scope for this
  release.
* **Windows / macOS / Linux.** Tracer's documented route is a C/C++ breakpad
  integration with `symupload.py` / `crashupload.py`.

On all of these, Dart error reporting is available by registering the pure-Dart
transport explicitly:

```dart
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';

void main() {
  TracerPlatform.instance = TracerHttpTracer(
    facts: PlatformClientFacts(),
    sdkVersion: '0.1.0',
  );
  Tracer.initialize(
    options: const TracerOptions(appToken: '<appToken>'),
    appRunner: () => runApp(const MyApp()),
  );
}
```

Native crashes of the host process are **not** covered by this path.

## Platforms with no implementation at all

If nothing is registered, `TracerPlatform.instance` is
`UnsupportedTracerPlatform`: every call succeeds and does nothing,
`isEnabled` is `false`, and one diagnostic line is printed the first time the
integration is used. `appRunner` still runs exactly once. Nothing throws.
