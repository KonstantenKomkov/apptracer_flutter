# apptracer_flutter_desktop

Experimental `TracerPlatform` adapter using the official **sentry_flutter 9.30.1**
SDK for macOS/Windows. Not published; platform acceptance is pending.

Add this optional package alongside `apptracer_flutter`, set
`TracerPlatform.instance = SentryDesktopTracer()` before `Tracer.initialize`, and
pass the Tracer project's Sentry DSN through `TracerOptions.dsn`. Release,
environment and dist use the existing options. Never embed a symbol plugin token.
macOS now registers the optional adapter automatically; explicit assignment is
only needed when selecting the backend yourself. See [example](example/README.md)
for the separate macOS runner and local release transport checks.

Tracer owns appRunner, Dart error handlers and user filters. Do not initialize or
write to Sentry separately. Existing SDK ownership is rejected without closing it.
Automatic sessions, tracing, profiling, replay, logs/metrics, screenshots and Dart
error integrations are disabled. Filtered keys/breadcrumbs cannot be restored by
SDK scope merging. Original Dart stacks are retained under
`contexts.apptracer.dart_stack_trace`; issueKey maps to fingerprint.

Native crashes do not run Dart beforeSend. Do not put sensitive values into native
scope expecting the Dart callback to filter a later native crash.

**Server-side native macOS symbolication is unsupported in the tested integration**
(sentry_flutter 9.30.1 / Cocoa 8.58.4, Tracer DESKTOP project). SIGABRT delivery is
confirmed, but matching desktop symbols do not restore source files/lines; the
Apple dSYM endpoint rejects DESKTOP projects. Local dSYM symbolication works.
Ordinary symbolic Dart stacks are sent separately. See the
[acceptance record](../../docs/macos-symbols-acceptance.md).

Disabled/deferred bootstrap does not start the SDK. On macOS, stop gates Dart and
native network admission, cancels in-flight requests, and closes Cocoa SDK; it waits
for session invalidation before acknowledging. Failures remain `error`. After a
native initialization attempt, restarting collection requires a new process.
`stopAndClearCollection` also removes this adapter's queue, crash files, persisted
scope/identity and Cocoa async diagnostic log; it returns `restartRequired` after
native init, or `disabled` before it. An empty file prevents late cache recreation.

`preservePreviousReports=false` (default) purges before native startup. `true`
retains reports from an ordinarily terminated/crashed process. Any preceding stop,
including an explicit stop before first init, revokes replay even with `true`.
Already transmitted bytes/server data cannot be recalled. Cleanup covers the new
`Library/Application Support/apptracer_desktop/<bundle-id>/v1` namespace (inside the
container for sandboxed apps), plus `async.log`. Legacy SDK caches are neither
imported nor automatically deleted; app owners must plan migration cleanup.
System macOS crash logs are not deleted.

The macOS bridge uses public Cocoa 8.58.4 APIs and CocoaPods; SPM is not supported
by this bridge. Official SDK serialization, crash handling and queueing remain in
use; a session-local URLProtocol gates network delivery. See the
[local lifecycle evidence](../../docs/macos-lifecycle-acceptance.md).
Windows purge remains unsupported; macOS results do not establish Windows support.

The main package's dependency graph is unchanged. Adding this optional package to
a combined mobile/desktop app also pulls in Sentry's iOS/Android native dependencies;
use a separate desktop consumer until that graph has been verified.

To migrate from the git-only manual protocol package, replace
`apptracer_flutter_sentry` / `SentryProtocolTracer` with this package /
`SentryDesktopTracer`. Never run both transports.

Run `flutter pub get`, `flutter analyze`, `flutter test` on macOS. Tests exercise
the official SDK with a mocked native channel, not live Tracer ingestion. See the
[Russian README](README.md) for the setup example and full limitations.
