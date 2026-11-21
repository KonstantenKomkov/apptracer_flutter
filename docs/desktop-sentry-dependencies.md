# Desktop Sentry dependency inventory

Current production pin: `sentry_flutter 9.30.1`; verified native family:
sentry-native 0.16.6 and Cocoa 8.58.4. This inventory is for candidate reviews,
not a claim that newer versions work.

## Internal Dart APIs

| Source | Used for | Public alternative / migration | Detection |
|---|---|---|---|
| `src/integrations/native_load_debug_images_integration.dart` | exact native debug images for AOT symbols | Keep private until an equivalent public integration exists; compare class and callbacks at every candidate | `linux_dart_symbols_test`, `windows_dart_symbols_test`, macOS symbol workflow |
| `src/integrations/native_sdk_integration.dart` | native ownership and lifecycle | Evaluate the public integration registry before replacing; do not assume lifecycle is equivalent | deferred start, close failure and prestart stop tests |
| `src/integrations/widgets_flutter_binding_integration.dart` | binding-safe integration startup | Public `Integration<SentryFlutterOptions>` remains the boundary | `sdk_delivery_test`, `initialization_failure_test` |
| `src/native/c/binding.dart` | `sentry_options_s` layout | No public equivalent; candidate must revalidate struct layout rather than blindly update | resolver/analyze, Linux/Windows release and native crash |
| `src/native/c/sentry_native.dart` | options construction, native init/close and scope contexts | Replace only with a public lifecycle/scope API that preserves stop/clear semantics | all desktop unit tests and platform runtime suites |
| `Sentry.currentHub.options` | startup error visibility and safe option inspection | No equally detailed public hook; preserve guarded use | `sdk_delivery_test` and initialization failure test |

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

## Candidate evidence model

`/.github/workflows/sentry-candidate.yml` first runs resolver, analyze and unit
tests in a disposable checkout. It then invokes existing preparation, lifecycle,
native crash, offline/retry and symbol workflows with a candidate marker. A
machine-readable summary lists every OS and explicit failed/blocked stages. No
workflow merges or publishes a package.

Passing a candidate does **not** change `pubspec.yaml`. A pin-changing PR must
also include hosted consumer evidence without monorepo overrides and a final
live Tracer smoke. Rollback is simply retaining the last accepted pin above;
there is no hidden range expansion.
