# Task 23 release preparation — 2026-11-13

**Prepared, not published.** This record covers the package release only.
Updating farming is a separate task. No pub.dev upload or release tag has been
created by this preparation.

| Publication order | Package | Version | Required sibling versions |
| --- | --- | --- | --- |
| 1 | `apptracer_flutter_platform_interface` | **0.2.1** | None |
| 2 | `apptracer_flutter_android` | **0.4.0** | `apptracer_flutter_platform_interface ^0.2.1` |
| 3 | `apptracer_flutter` | **1.2.0** | `apptracer_flutter_android ^0.4.0`, `apptracer_flutter_platform_interface ^0.2.1` |

`apptracer_flutter_ios`, `apptracer_flutter_web` and `apptracer_flutter_http`
remain at their published 0.2.0 versions. The optional desktop package is
unchanged. The example now requires `apptracer_flutter ^1.2.0`.

## Release notes

Android SDK 1.6.1 with deferred initialization can start a fresh collection
session after successful full cleanup, without restarting the process. Logout
uses `stopAndClearCollection()`; a new authorized `startCollection()` creates
fresh executors, identifiers, native crash writer and ANR watchdog. Old queued
reports and account context are removed before the next session starts.
Failed cleanup leaves collection closed.

`Tracer.pauseCollection()` and `resumeCollection()` provide a temporary pause
that retains context. Pause does not revoke consent or cancel admitted uploads.
Pending Dart operations cannot reopen a revoked session.

`runHeapDump(tag: ...)`, `runDiskUsage()` and `setHeapDumpEnabled(bool)` expose
optional Android diagnostics. The host explicitly installs the modules and a
synchronous native heap provider. `TracerDiagnosticResult` distinguishes
`invoked`, `disabled`, `unsupported` and `error`; invocation is not confirmation
of delivery. Existing platform implementations have unsupported defaults.

Full cleanup with Android automatic initialization, SDK 1.4.0/1.5.2, or iOS
SDK 1.5.2 still requires a process restart. Optional diagnostic modules are
outside managed deferred cleanup; heap dumps can pause the VM/UI and offline
samples can be lost without retry. The existing Kotlin file/line recovery
defect and full Flutter configuration-cache limitation remain unchanged.

See the package changelogs for scoped changes and
[task 23 acceptance](task-23-collection-lifecycle.md) for release/R8 evidence,
including repeated sessions, offline purge, JVM/native/ANR recovery and actual
public Dart heap/disk sample uploads. These are the existing implementation
checks; this preparation does not claim new device or Tracer-console results.

## Preparation checks

The implementation source is
`d9c9c3797dbf7a07982578d38bf477b45a5f146a`, with the release metadata and packaging
changes in this preparation. Its [CI run](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/43426116097)
passed all 11 jobs. Local preparation used Flutter 3.47.4 / Dart 3.13.3.

An isolated export excluded unrelated workspace changes. Only the new
`apptracer_flutter_android` and `apptracer_flutter_platform_interface` versions
used local overrides; unchanged iOS/Web/HTTP packages resolved from pub.dev.
The example additionally used the local `apptracer_flutter` package for tests.

The Ubuntu external-consumer check now exports the matching Android/interface
candidates as well. Its previous candidate mode tried to resolve unpublished
versions from pub.dev. Candidate overrides are explicit, restricted to those
two dependencies, checked against the resolved graph, and reported separately
from the unchanged hosted-consumer check. Exported pubspecs retain their hosted
version constraints. Local resolution of both the package and an external
consumer passed; full Ubuntu build/runtime validation runs in CI.

- Formatting and analysis passed for all three packages and the example.
- Tests passed: 47 in `apptracer_flutter_platform_interface` (one browser-only
  test skipped in this VM run), 2 in `apptracer_flutter_android`, 90 in
  `apptracer_flutter`, and 1 example widget test: **140 passed, 1 skipped**.
- All three publication dry-runs exited successfully with **zero warnings**.
  `apptracer_flutter_platform_interface` had zero hints;
  `apptracer_flutter_android` had one temporary override hint;
  `apptracer_flutter` had two temporary override hints, one per overridden
  dependency. These are preparation checks, not final hosted validation.
- Explicit package `.pubignore` rules exclude generated output even when an
  export has no enclosing Git repository. The initial check found a 14 MB test
  cache in the interface/Android packages; corrected dry-runs exclude it.
- The final package file lists contain 24 / 42 / 119 files respectively, with
  reported compressed sizes 29 KB / 49 KB / 182 KB. Every listed file matches
  its source. Local overrides, locks, build caches, environment files, signing
  files and generated plugin registrants are absent from those lists.

Local logs and source-file manifests are in `build/release-1.2.0/` (ignored).
The [machine-readable preparation record](release-1.2.0.json) records the checks
and manifest digests. These digests identify sorted source-file manifests;
they are **not** hashes of uploaded pub.dev archives.

## Publication procedure

Publish only after the release preparation is committed and its CI passes.
Create a clean export of that commit, remove all `pubspec_overrides.yaml` files,
and process the packages in the table order. Do not weaken dependency bounds
to bypass a predecessor that has not reached the pub.dev index yet.

For each package, after its predecessor is available on pub.dev:

```sh
flutter pub get --no-example
dart pub publish --dry-run
dart pub publish
```

The final dry-run must use hosted dependencies with no overrides and report
zero warnings and zero hints. Do not pass `--skip-validation` or
`--ignore-warnings`. Inspect each package's file list before upload.

After all three uploads, resolve and analyze the example without overrides,
and build a fresh Android consumer using `apptracer_flutter ^1.2.0`, matching
SDK/BOM/Gradle plugin 1.6.1, and the audited Android toolchain from
[publishing.md](publishing.md). Verify the hosted dependency versions and
absence of Git/path overrides. Download each pub.dev archive, verify its hash
against pub.dev metadata and compare its files with the release commit.
Only then record publication and the release-event tag `v1.2.0`.

The final hosted checks and archive verification are pending publication;
local preparation cannot substitute for them.
