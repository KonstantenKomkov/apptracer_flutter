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

Native crashes do not run Dart beforeSend. Native data filtering, live delivery,
symbolication and collection revocation require separate acceptance.

Disabled/deferred bootstrap does not start the SDK. Stop gates Dart immediately,
then calls SDK close; close failure is reported as error. Restart after a native
initialization attempt requires a new process. **Native purge is not implemented:**
stopAndClearCollection returns unsupported. Previously cached reports may upload
on the next process start, even with preservePreviousReports=false. Do not use this
experimental package where verified native consent revocation is required.

The main package's dependency graph is unchanged. Adding this optional package to
a combined mobile/desktop app also pulls in Sentry's iOS/Android native dependencies;
use a separate desktop consumer until that graph has been verified.

To migrate from the git-only manual protocol package, replace
`apptracer_flutter_sentry` / `SentryProtocolTracer` with this package /
`SentryDesktopTracer`. Never run both transports.

Run `flutter pub get`, `flutter analyze`, `flutter test` on macOS. Tests exercise
the official SDK with a mocked native channel, not live Tracer ingestion. See the
[Russian README](README.md) for the setup example and full limitations.
