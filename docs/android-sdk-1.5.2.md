# Android SDK 1.5.2 update — 2026-10-16

The Android package compiles against Tracer 1.5.2. The example uses the matching
BOM and Gradle plugin. Both packages were published as 0.2.1 from `v0.2.1`
(`31a4f5b`); see [the publication record](publishing.md#stable-021--2026-10-16).
No Dart channel or platform-interface change is needed: Android
reads crash configuration before Flutter starts. iOS, web, HTTP and Sentry
implementations keep their existing versions.

## Distribution and configuration

Keep `https://nexus-external.vkteam.ru/repository/maven/` in both plugin and
dependency repositories. The [1.5.2 BOM](https://nexus-external.vkteam.ru/repository/maven/ru/ok/tracer/tracer-platform/1.5.2/tracer-platform-1.5.2.pom)
and [plugin marker](https://nexus-external.vkteam.ru/repository/maven/ru/ok/tracer/ru.ok.tracer.gradle.plugin/1.5.2/ru.ok.tracer.gradle.plugin-1.5.2.pom)
were available there on the audit date. The public quick-start still showed
1.4.0, so this update was checked against the actual vendor artifacts.

`TracerAutoConfig` now reads the application metadata boolean
`ru.apptracer.flutter.experimentalTombstoneEnabled`. Missing or false leaves
tombstones disabled and retains the non-fatal rate limit. True calls
`CrashReportConfiguration.Builder.setExperimentalTombstoneEnabled(true)`.
The automatic provider, `TracerApplication` and the default deferred host
configuration all use the same reader. A host implementing
`HasTracerConfiguration` still owns its complete configuration; it must enable
the builder flag itself, as the example does.

Tombstones need Android 12 / API 31+, and only the `tracer-crash-report` module.
The optional native module remains useful below Android 12. The new feature
supports symbolication of system libraries; Dart AOT symbolication is not
established by this update. Perform a clean build after changing SDK versions.

## Deferred adapter audit

The adapter accepts exactly 1.4.0 and 1.5.2. Historical `Sdk140*` class and tool
names remain to avoid gratuitous native API/script renames. The default path
does not call the new builder method, preserving hosts on 1.4.0. Enabling
tombstones requires upgrading the host SDK to 1.5.2.

Compared the published `classes.jar` bytecode with the cached 1.4.0 artifacts:

- `CoreTracerConfiguration`, `Tracer`, the configured executors and the
  `SequentialExecutor` queue retain the contracts used for startup/revocation.
  No additional crash-module initializer was introduced.
- `ExitReporter` replaces the ANR-only reporter. Startup selects ANR records
  on API 30+ and native exit records on API 31+ when tombstones are enabled.
  Reporting and uploads run through the controlled SDK background/IO queues.
- Exit reports require the previous launch's system state. Clearing
  `cache/tracer` before startup removes that state, so Android's retained exit
  records alone do not reconstruct a report. The OS history itself is not
  deleted by the plugin. `preservePreviousReports` and the persisted purge
  obligation retain their existing meaning.
- Session start timestamps now account for process uptime. Session fields,
  log/tag stores, their locks and terminal cleanup states remain compatible.
- The native module now depends on `tracer-native-bindings:0.1.41-android`.
  Its `Minidump.getInstance()` / `uninstallMinidumpWriter()` signatures remain
  available. Java signature checks do not establish JNI runtime behavior.
- The fatal-handler chain and watchdog shutdown fields retain their names.
  Existing consumer R8 rules cover the adapter's reflection dependencies.

The tools accept matched audited SDK pairs. SHA-256 of extracted 1.5.2 JARs:

| Artifact | SHA-256 |
|---|---|
| `tracer-commons` | `9cb045087b426cc8215d00556815a5cf0560c18c96fcf91c21ddd59b53fc82ae` |
| `tracer-crash-report` | `d0825dfe7b270ae62b3eb7e120236aec74f07aaff862887127c7633fe923d925` |

## Validation

- Android JUnit tests against SDK 1.5.2, including tombstones off by default,
  explicit opt-in, and retention of the non-fatal rate limit. The test
  dependencies do not include `tracer-crash-report-native`.
- JVM checks for executor revocation, background queue drain, endpoint
  revocation, diagnostic buffer cleanup, fatal admission/drain and all
  reflection names, using the 1.5.2 vendor classes.
- Flutter analysis and tests for the Android implementation, facade and example.
- Clean ARM64 release APK builds with and without SDK 1.5.2, including R8.
  The SDK build used placeholder tokens and a temporary Gradle init script
  disabling vendor mapping/symbol upload tasks; no production upload occurred.
  The release R8 mapping retains the 12 checked reflection class names.
- Default configuration and installation compiled against 1.5.2 also ran
  against the 1.4.0 runtime classes without linkage errors.
- Publication dry-runs from the release export report zero warnings for both
  0.2.1 archives. Dependencies resolve from pub.dev without overrides, with
  Android published first. Both downloaded archives match the release commit.
- GitHub CI passed for release commit `31a4f5b` with Flutter 3.35.7.

The local Flutter installation is 3.47.4; the repository CI is pinned to
3.35.7. Local Gradle checks use `-PskipDependencyChecks=true` with the existing
Gradle 8.12 wrapper to bypass Flutter 3.47's newer minimum version check.

### Remaining device acceptance

Earlier release/R8, network and crash-recovery evidence in
[the lifecycle log](native-collection-consent.md) applies to **1.4.0**.
Before claiming full 1.5.2 device verification:

1. On API 31+, enable tombstones without the native module, cause a native
   crash, restart with preservation authorized, and confirm a TOMBSTONE in
   Tracer with system frames symbolicated.
2. Repeat with tombstones off and on API 30 or lower; no TOMBSTONE should be
   sent. Retain the native module when testing native reporting below API 31.
3. Verify both the manifest/default configuration and a custom
   `HasTracerConfiguration`, in automatic and deferred builds.
4. Repeat deferred release/R8 tests for purge-before-start, retained previous
   reports, account change, offline/in-flight stop, native writer uninstall,
   ANR and a process restart after withdrawal. A purge obligation must override
   preservation, and old system exit reports must not cross that boundary.

These scenarios require runtime evidence; static compatibility and JVM tests
do not replace delivery confirmation in Tracer.
