# Desktop Sentry dependency inventory

Published production pin: `sentry_flutter 9.30.1`; verified native family:
sentry-native 0.16.6 and Cocoa 8.58.4. The 2.0.0 source candidate selects
`sentry_flutter 10.6.0`, sentry-native 0.17.6 and Cocoa 9.35.0. It remains subject
to platform, hosted-consumer and live acceptance; this inventory is not a claim
that every newer version works.

## Internal Dart APIs

| Source | Used for | Public alternative / migration | Detection |
|---|---|---|---|
| `src/debug_images/native_load_debug_images_integration.dart` | exact native debug images for AOT symbols | Keep private until an equivalent public integration exists; moved from `src/integrations` in 10.6.0 | `linux_dart_symbols_test`, `windows_dart_symbols_test`, macOS symbol workflow |
| `autoInitializeNativeSdk = false` | native ownership and lifecycle | Public option routes Windows scope and debug-image calls to the adapter-owned SDK. The integration allowlist removes the default initializer without importing its moved class. | deferred start, close failure and prestart stop tests |
| `src/bindings/widgets_flutter_binding_integration.dart` | binding-safe integration startup | Moved from `src/integrations`; public `Integration<SentryFlutterOptions>` remains the boundary | `sdk_delivery_test`, `initialization_failure_test` |
| `src/native/c/binding.dart` | opaque `sentry_options_s` pointer | SDK allocates options. The adapter uses C setters and verifies their signatures, enum values and pointer widths | resolver/analyze, Linux/Windows release and native crash |
| `src/native/c/sentry_native.dart` | options construction, native init/close and scope contexts | Replace only with a public lifecycle/scope API that preserves stop/clear semantics | all desktop unit tests and platform runtime suites |
| `SentryFlutter.init` configuration callback | actual initialized options | The adapter checks package metadata lookup, the enabled hub and its own native integration marker. Close requires the native lifecycle acknowledgement. | `sdk_delivery_test` and initialization failure test |
| `SentryStackTrace.baseAddr` and `buildId` constructor arguments | associate AOT frames with the exact debug image | Re-evaluate public debug-image mapping on each update | Dart symbol suites and event mapping |

Public Sentry APIs used deliberately: `Sentry.init`, `Sentry.close`,
`Sentry.captureEvent`, `SentryException`, `SentryStackTrace`, `SentryEvent`,
`SentryStackFrame`, `Breadcrumb`, `Contexts`, `Mechanism`, `SentryId` and
`Integration<SentryFlutterOptions>`. These are not guaranteed stable either;
event mapping and exact envelope tests run for each candidate.

## Native symbols and platform helpers

| Symbol / helper | Purpose | Detection |
|---|---|---|
| `sentry_options_set_require_user_consent` | gate native work before consent | deferred/disabled scenarios |
| `sentry_user_consent_give` / `sentry_user_consent_revoke` | native consent lifecycle | stop/clear/revoke and no-replay scenarios |
| `sentry_options_set_cache_keep` | retain authorized offline queue | offline/retry scenarios |
| `sentry_options_set_http_retry` | native retry policy | offline/retry and discard scenarios |
| `sentry_options_set_shutdown_timeout` | bounded in-flight cancellation | `native-inflight`, close failure |
| `sentry_envelope_deserialize` / `sentry_capture_envelope` | enroll native cached envelopes before startup | `linux_storage_test`, `windows_storage_test`, offline runtime |
| `sentry_is_enabled` | reject second native owner | concurrent-owner scenario |
| `sentry_options_set_handler_path` / `sentry_options_set_crash_reporting_mode` | package and configure native crash handler | packaging, missing handler, native crash |
| `sentry_init` / `sentry_close` through generated binding | native process lifecycle | all release/runtime scenarios |
| `getuid`, `syscall`, `close`, `poll` from libc | owned Linux queue lock, PID-reuse and cancellation checks | Linux storage and native runtime suites |
| `apptracer_windows.dll` helpers | Windows queue reparse-point and ownership safety | Windows storage, junction and concurrent-owner suites |

The Linux daemon wraps `sentry_value_set_by_key` at link time. The Windows
daemon compiles a wrapper around `sentry_crash_daemon.c` and packages the
`sentry-crash` and `sentry-wer` targets. Both integrations depend on upstream
build internals. The relocated native crash and source-line probes exercise
these hooks. On macOS the candidate pins the same `Sentry-Static` binary as
Sentry Flutter in its Swift package
and sets `urlSession`, `cacheDirectoryPath` and `shutdownTimeInterval` for
consent and cancellation. The SPM lock, compiled checkout and lifecycle suite check
those dependencies. A new Cocoa pin requires a separate adapter change.

## Candidate evidence model

The monthly run selects the latest stable `sentry_flutter` release on pub.dev.
Manual dispatch accepts an exact version. Pull requests changing the candidate
pipeline use the accepted pin as a control. Every checkout applies the same
exact version to its disposable desktop manifest, including the path dependency
used by the release example.

All three prechecks must resolve, analyze and pass unit tests before release
jobs start. Windows runtime downloads the release artifact from that run.
The `sentry-candidate-report` artifact records the actual job and step results
on each OS and links to the probes. Grouped runtime steps retain their individual
JSON files in the platform artifacts. Successful builds record the example's
resolved Flutter SDK package, Sentry Cocoa or sentry-native, and Flutter/Dart
toolchain. A skipped suite or missing build identity prevents a passing result.

A pin-changing PR also requires hosted consumer evidence without monorepo
overrides and a final live Tracer smoke. For rollback, restore the previous
accepted Dart and Cocoa pins together with their matching adapter revision.

## Candidate 10.6.0 on 2026-11-22

Dependency resolution succeeded on macOS 15, Ubuntu 22.04 and Windows 2022.
Analysis of the pre-migration adapter failed on all three runners. That adapter imported integrations moved
in 10.6.0 and used the former options and SDK logger API. Release builds and
native runtime suites were skipped by the workflow. The accepted production
pin remains 9.30.1. [Candidate run](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/45007640137).

The 2.0.0 source migration adopts the Flutter 3.44 minimum and Swift Package
Manager. Published 1.0.1 supports Flutter 3.24 and uses CocoaPods.
[10.6.0 manifest](https://pub.dev/api/packages/sentry_flutter/versions/10.6.0)
and [upstream Apple packaging change](https://github.com/getsentry/sentry-dart/pull/3879).
