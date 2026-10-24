# apptracer_flutter_desktop

[Русский](README.md)

Experimental `TracerPlatform` adapter using the official **sentry_flutter 9.30.1**
SDK for macOS/Windows/Ubuntu Linux. Unpublished; macOS arm64 and Ubuntu x64 are
accepted within their documented scope, while Windows acceptance remains pending.

Ubuntu 22.04 x86_64 uses the official native queue for SDK-serialized Dart events
and native reports. Linux requires `SENTRY_NATIVE_BACKEND=native` and an executable
`lib/sentry-crash` in the bundle (see the example build helper).
The Linux CMake hook resolves native source frames inside the crash daemon using
matching Breakpad maps in `lib/symbols`. The example build helper generates these
from the same build's DWARF; this native store does not contain Dart maps. Missing
or mismatched maps preserve the original SDK report. The hook is pinned to
sentry-native 0.16.6 and must be re-audited when upgrading the SDK.
For Dart AOT, the adapter reads an optional compact map from
`lib/apptracer-dart-symbols/<build-id>.json.gz` before SDK serialization. Stack,
loaded ELF and map build IDs must agree; the original stack is retained.
The example helper generates this map by default. It exposes function names and
source paths, weakening obfuscation; opt out with
`TRACER_BUNDLE_DART_SYMBOLS=0 bash tool/build_linux_desktop.sh`.
Full DWARF and source code remain outside the bundle.
After consent, Linux adds distro/kernel, architecture and DMI model/vendor;
it does not read hostname, serial or machine-id. Tracer displays these fields
under Data → Other/Context. Its C/C++ receiver still has limitations in the
OS/device widgets and the `Stacktrace not available` caption, which can remain
even when source files and lines are present.
Linux registration is automatic. Stop revokes replay and
cancels owned uploaders; restarting collection requires a new process. Live Tracer
delivery, source frames and grouping were verified separately on an Ubuntu
22.04.5 x64 VM; see the tested environments and results in the
[Linux commands and record](../../docs/linux-preparation.md).

For an external Ubuntu app, follow the
[CMake and packaging setup](../../docs/desktop-migration.md#ubuntu-linux-consumer):
set the bundle install prefix before plugins, omit the unused JNI runtime and
install `sentry-crash` as PROGRAMS. A pubspec dependency alone is insufficient.
Verified with glibc 2.35, GTK 3 and X11; uploader cancellation requires kernel ≥5.3
and `/proc`. Ship the whole bundle with executable permissions; the target does
not need Flutter/Java. Generate symbols using tools from the same repository
revision; client maps need no plugin token. Hosted facade 0.2.1 predates the
stable obfuscated `FlutterError` name fix: use reviewed facade source by path/git
for that fix until 0.2.2 is published.

Add this optional package alongside `apptracer_flutter`, and
pass the Tracer project's Sentry DSN through `TracerOptions.dsn`. Release,
environment and dist use the existing options. Never embed a symbol plugin token.
macOS/Windows/Linux register the optional adapter automatically; explicit assignment is
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

## Windows preparation

The optional package now registers on Windows. The x64 example includes an
explicit native crash probe, runtime DSN selection and a loopback acceptance
driver. Windows x64 release build, Dart/native loopback delivery and native queue
recovery after HTTP 503 passed in CI. Stop/clear and live Tracer acceptance remain pending. See
[Windows preparation](../../docs/windows-preparation.md). Default startup (previous report
preservation disabled) returns `unsupported` before SDK initialization, because
Windows queue cleanup is not implemented. The experimental example explicitly
preserves reports. Stop/clear and native replay revocation remain unverified.

## External consumer and migration

See [desktop-migration.md](../../docs/desktop-migration.md) for installation
without monorepo overrides, CocoaPods setup, legacy-cache ownership and the
package dry-run procedure. The tested baseline is Flutter 3.47.4 / Dart 3.13.3,
sentry_flutter 9.30.1 / Cocoa 8.58.4 on macOS arm64. The bridge deployment target
is macOS 12.0; this is not runtime acceptance on every older OS or Intel.
