# Desktop installation and migration

The optional `apptracer_flutter_desktop` package is published at 2.0.0.
The accepted macOS scope is recorded in
[macos-lifecycle-acceptance.md](macos-lifecycle-acceptance.md); Ubuntu 22.04.5
x86_64 VM evidence is in [linux-preparation.md](linux-preparation.md).
Windows 11 x64 evidence is in [windows-local-acceptance.md](windows-local-acceptance.md).
Aurora is not supported by this adapter.

## Sentry upgrades

Desktop 2.0.0 uses `sentry_flutter 10.6.0`, sentry-native 0.17.6 and Cocoa
9.35.0. See the
[internal API and native symbol inventory](desktop-sentry-dependencies.md).
`/.github/workflows/sentry-candidate.yml` runs monthly and on demand in isolated
checkouts, with per-OS machine-readable results. It never merges or publishes.
The macOS release candidate passed a live Tracer smoke test for handled Dart,
Flutter and unhandled async errors. [Task 33](tasks/task-33-sentry-10-migration.md)
records the event IDs and the clean pub.dev consumer check.

On macOS this upgrade changes delivery during server outages. Cocoa 8.58.4 kept
a cached envelope after HTTP 503. For desktop 2.0.0 we accepted the default
Cocoa 9.35.0 behavior. After an HTTP 5xx, including 503, the SDK deletes the
envelope and moves on, so an event rejected during an outage can be lost. A dropped connection with
no HTTP response retains the envelope for an authorized restart with
`preservePreviousReports: true`. Stop or clear still revokes replay. The
lifecycle probe checks the original event ID on that restart. Roll back to
desktop 1.0.1 with CocoaPods and Sentry Flutter 9.30.1 if 503 retention is required.
[Cocoa 8.58.4 transport](https://github.com/getsentry/sentry-cocoa/blob/8.58.4/Sources/Sentry/SentryHttpTransport.m)
and [Cocoa 9.35.0 transport](https://github.com/getsentry/sentry-cocoa/blob/9.35.0/Sources/Sentry/SentryHttpTransport.m).

## External application

Install the facade and optional desktop adapter from pub.dev:

```yaml
dependencies:
  flutter:
    sdk: flutter
  apptracer_flutter: ^1.5.0
  apptracer_flutter_desktop: ^2.0.0
flutter:
  config:
    enable-swift-package-manager: true
```

For source development, a pinned git revision or isolated path copy is also
supported. The repository's `pubspec_overrides.yaml` files use paths specific to its
checkout. Pub applies overrides from the consuming app. Production consumers
resolve siblings from pub.dev. The staged consumer generates overrides pointing
to its exported siblings. [Dart dependency rules](https://dart.dev/tools/pub/dependencies#dependency-overrides).

Published 1.0.1 requires CocoaPods. For 2.0.0, enable Swift
Package Manager and set the Runner deployment target to at least 12.0; its
[Package.swift](../packages/apptracer_flutter_desktop/macos/apptracer_flutter_desktop/Package.swift)
shares Cocoa 9.35.0 with Sentry Flutter 10.6.0. The binary package manifest
requires Swift tools 6.0. Enable
`com.apple.security.network.client` in the sandboxed release entitlements.
Use the Swift Package Manager bridge for 2.0.0.

For a universal macOS release with Xcode 27.0, use the tested Flutter 3.47.4
toolchain. At the declared minimum of Flutter 3.44.0 / Dart 3.12.0, Flutter's
framework-copy step passes both architectures to `lipo -verify_arch` in one
call. Xcode 27.0 rejects that call even when the framework contains both
slices. An arm64-only release built and delivered all three smoke events on
this combination.

The adapter registers automatically on macOS/Windows/Ubuntu Linux. Call the normal
`Tracer.initialize` API with the target project's DSN; do not call
`SentryFlutter.init` in addition. For deferred consent, set
`nativeInitialization: TracerNativeInitialization.deferred` and explicitly
start collection after authorization. Inspect the returned collection state.
Use separate projects/configuration for each target. Plugin upload tokens belong
only in the symbol-upload environment, never in Dart defines or the app bundle.

## Ubuntu Linux consumer

Tested baseline: Ubuntu 22.04.5 x86_64, glibc 2.35, kernel 5.15, GTK 3,
X11/Xvfb, Flutter 3.47.4 / Dart 3.13.3, CMake 3.22 and Clang/LLVM 14.
The lifecycle implementation requires kernel ≥5.3 and `/proc` for pidfd-based
owned-uploader cancellation. Wayland, ARM64 and other distributions are not
covered by this acceptance. Use a C/C++ Tracer project and its Sentry DSN.

Install build dependencies on Ubuntu:

```sh
sudo apt-get install clang llvm-14 cmake ninja-build pkg-config libgtk-3-dev \
  libgles2 libcurl4-openssl-dev liblzma-dev openjdk-17-jdk xvfb
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export SENTRY_NATIVE_BACKEND=native
```

JNI is a transitive build dependency of the pinned SDK; this Linux adapter
does not use it at runtime. For a new `flutter create --platforms=linux` app,
apply these changes to `linux/CMakeLists.txt`:

1. Immediately after `project(runner LANGUAGES CXX)`, before any plugin projects:

   ```cmake
   if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
     set(CMAKE_INSTALL_PREFIX "${PROJECT_BINARY_DIR}/bundle" CACHE PATH "Bundle" FORCE)
   endif()
   ```

2. Inside `foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})`, before `install`:

   ```cmake
   if(bundled_library STREQUAL "$<TARGET_FILE:jni>")
     continue()
   endif()
   ```

3. At the end of the file, after the template's bundle cleanup/install rules:

   ```cmake
   add_dependencies(${BINARY_NAME} sentry-crash)
   install(PROGRAMS "$<TARGET_FILE:sentry-crash>"
     DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
   ```

These settings prevent JNI from redirecting the install prefix, avoid unused
JVM runtime dependencies, and retain the crash daemon's executable permission.
For native source maps, append this after the runner target definition in
`linux/runner/CMakeLists.txt`:

```cmake
target_compile_options(${BINARY_NAME} PRIVATE -g)
```

Build with the backend environment variable still set:

```sh
flutter pub get
flutter build linux --release --obfuscate --split-debug-info=build/symbols
```

The package's minimum Flutter constraint is a resolver floor, not runtime
acceptance of every Flutter version. Keep the exact SDK pin. If switching
from a cached Crashpad configuration, regenerate the Linux build directory
with `flutter clean` before rebuilding.

For source frames, use the tools from the same reviewed repository revision.
Here `APPTRACER_REPO` points to that checkout and `APP_EXECUTABLE` is the
application's `BINARY_NAME` (not the example name):

```sh
bundle=build/linux/x64/release/bundle
python3 "$APPTRACER_REPO/tool/prepare_linux_symbol_tools.py" --output build/symbol-tools
python3 "$APPTRACER_REPO/tool/prepare_linux_runtime_symbols.py" \
  --bundle "$bundle" --executable "$APP_EXECUTABLE" --dump-syms build/symbol-tools/dump_syms
python3 "$APPTRACER_REPO/tool/prepare_linux_dart_runtime_symbols.py" \
  --bundle "$bundle" --symbols build/symbols/app.linux-x64.symbols \
  --dump-syms build/symbol-tools/dump_syms
```

The last command is optional: its compact map exposes names/source paths and
weakens Dart obfuscation. Without it, original events still arrive but automatic
Dart source lines are unavailable. Keep full split-debug-info, ELF/DWARF and
build IDs privately for diagnosis. Maps must match the distributed binaries;
do not run strip/ELF rewriting after producing them without rechecking identity.

Distribute the **entire bundle**, retaining executable permissions (for example
with tar). The target needs GTK 3, libcurl, EGL/GLES and its display drivers;
Flutter, Java, LLVM and Python are not application runtime dependencies.
Check `ldd` for the runner, every `.so`, and `lib/sentry-crash` on the target.
Launch the runner directly; `TRACER_LINUX_SENTRY_DSN` is the repository example's
environment convention. An external app must pass its chosen DSN explicitly
through `TracerOptions.dsn`. Plugin tokens are not required for client maps.

The queue lives outside the bundle under
`$XDG_DATA_HOME/apptracer_desktop/<executable-name>/v1` (fallback `$HOME/.local/share`).
Use a unique, stable executable name; concurrent processes cannot share this
namespace. After active stop/clear, handle `restartRequired` by starting a new
process. `preservePreviousReports:true` only preserves authorized reports;
revocation takes precedence. Retry covers network failures; HTTP 5xx are discarded
by this pinned native SDK. Sessions/crash-free/performance/replay are disabled.

Facade 1.0.0 preserves the `FlutterError` type name under obfuscation.
Public siblings resolve from pub.dev without monorepo overrides. Source-frame
decoding belongs to the adapter and is separate from that facade fix.

Run the external-consumer check from this repository on Ubuntu:

```sh
xvfb-run -a python3 tool/check_linux_consumer.py --output build/ubuntu-consumer-hosted
xvfb-run -a python3 tool/check_linux_consumer.py --candidate-facade \
  --output build/ubuntu-consumer-candidate
```

Each run builds a newly generated release app,
relocates it into a path with spaces/Cyrillic, checks automatic registration,
filtered data, deduplication, exact-build source frames and stop/clear using a
loopback receiver. The default app uses published facade 1.5.0 and desktop
2.0.0 with hosted dependencies. `--candidate-facade` tests and publish-dry-runs
the exported adapter and facade with their staged sibling dependencies. The exported `consumer-bundle.tar.gz` can
also be checked on a clean VM with `--bundle <extracted-bundle>`.

## Moving from the manual transport

For the facade 2.0.0 release, keep the manual transport archived at
`packages/apptracer_flutter_sentry` with `publish_to: none` and outside the
routine package checks. Existing Git subdirectory references and local paths
can still resolve to that directory. The archive has no scheduled removal.
[Consumer audit for issue #28](#manual-transport-consumer-audit).

1. On supported macOS, Windows 11 x64 and Ubuntu 22.04.5 x86_64, remove the
   archive's Git/path dependency, any matching dependency override, its Dart
   import and the manual `SentryProtocolTracer()` registration. Install the
   [desktop adapter](#external-application), which registers automatically.
   Remove any separate Sentry SDK initialization.
2. Keep the facade calls for errors, keys, breadcrumbs and user ID. Configure a
   Sentry DSN rather than an app token. Test with a new release identifier.
3. Decide how to dispose of legacy SDK caches in your own application. The new
   adapter owns only its isolated v1 directory and scoped Cocoa caches; it does
   not import or remove another transport's data. Use the old owner's cleanup
   API before removing it, where available. Do not recursively erase unrelated
   Library/Caches directories.
4. Account for additional native OS/device/app metadata and the fact that native
   crashes bypass Dart `beforeSend`. Review [privacy.md](privacy.md).
5. Treat macOS `restartRequired` after stop/clear as requiring a new process.
   Stop durably revokes replay. `preservePreviousReports: true` cannot restore
   reports after revocation; it applies to ordinary authorized restarts.
6. Retain matching binaries/dSYMs for local diagnosis. Server-side native macOS
   symbolication remains unsupported in the tested integration; delivery alone
   does not demonstrate symbolication or crash-free metrics.

The main facade does not depend on Sentry. Adding the desktop package to a shared
mobile/desktop application does add Sentry's transitive native mobile plugins;
conditional imports cannot remove them. A separate desktop app keeps those
dependencies out of an existing mobile graph.

### Manual transport consumer audit

On 24 November 2026 we checked the facade and desktop examples at `89443ee`
and 26 local checkouts of other Dart/Flutter projects. We searched package
manifests, overrides and lockfiles for `apptracer_flutter_sentry`, and Dart
sources for imports and `SentryProtocolTracer` registration.

| Checked source | Result |
| --- | --- |
| `apptracer_flutter`, including both examples | The only Dart matches were the archived implementation and its own tests. Neither example depends on the archive. |
| `farming` | Its earlier Git dependency at `e50788f5` selected `packages/apptracer_flutter`. At `ade43111` its lockfile resolves the facade to hosted 1.5.0. Neither revision uses the manual transport. |
| `vkid-flutter-sdk`, `vk_maps_mapkit`, `push_token_tester` and the other locally available applications and libraries | No archive dependency, import or registration was found. |

No checked application needs migration. Usage in third-party forks, private
repositories outside the workspace and other revisions remains unknown. Keeping
the directory in place preserves the path those consumers may have pinned.
[Issue #28](https://github.com/KonstantenKomkov/apptracer_flutter/issues/28).

## Windows consumer

Use `apptracer_flutter_desktop ^2.0.0` alongside `apptracer_flutter ^1.5.0`. Before
`flutter build windows --release`, set `$env:SENTRY_NATIVE_BACKEND = 'native'`.
The desktop FFI CMake target bundles the lifecycle helper, `sentry-crash.exe`,
`sentry-wer.dll` and app-local MSVC redistributable DLLs. Ship the entire Release
directory, including Flutter/Sentry DLLs and `data/`. Windows 11 x64 is the
tested local baseline; a fresh Windows 11 x64 VM without build tools also passed
the runtime/consumer checks. Windows 10 and ARM64 are untested.

Use an executable name unique to the application: the owned per-user namespace
is `%LOCALAPPDATA%/apptracer_desktop/<exe-name>/v1`. Concurrent instances with that
name cannot own collection simultaneously. The install directory can be read-only.
Do not migrate the old Crashpad queue; plan any legacy-cache cleanup separately.
Stop/clear revokes replay even when the next process requests preservation;
resuming after native initialization requires a new process.

Build with `--obfuscate --split-debug-info=build/symbols`, retain the exact PDB
and `app.windows-x64.symbols`, and optionally generate native/Dart compact maps
using the [Windows commands](windows-preparation.md). For another EXE use
`prepare_windows_runtime_symbols.py --executable <name.exe>` and its matching
PDB. Maps reveal source paths/function names but require no plugin token.
The app runs without maps; unknown frames retain original addresses/raw stacks.

Two reproducible consumer variants (from this repository root):

```powershell
. ./tool/use_windows_tools.ps1
python -X utf8 tool/check_windows_consumer.py --output build/windows-consumer-hosted --dump-syms D:\Tools\Symbols\dump-syms\dump_syms.exe
python -X utf8 tool/check_windows_consumer.py --candidate-facade --output build/windows-consumer-candidate --dump-syms D:\Tools\Symbols\dump-syms\dump_syms.exe
```

An optional `--native-source <directory>` reuses a complete, audited sentry-native
checkout matching the selected adapter (0.17.6 for 2.0.0, 0.16.6
for published 1.0.1). The default resolves published facade 1.5.0 and adapter
2.0.0 from pub.dev without overrides. The candidate uses isolated exports of the
adapter, facade and their siblings.
Both include the obfuscated FlutterError name fix.
The harness performs package dry-runs, builds obfuscated release, relocates it,
restricts PATH to Windows/System32 and verifies filtering/deduplication/source
frames/clear. This does not replace clean-machine testing.
[Local results and publication boundary](windows-local-acceptance.md).

Run the hosted consumer with the coordinated release versions:

```powershell
python -X utf8 tool/check_windows_consumer.py --hosted-desktop 2.0.0 --facade-version 1.5.0 --output build/windows-consumer-published --dump-syms D:\Tools\Symbols\dump-syms\dump_syms.exe
```

This mode checks that every Tracer dependency resolves from pub.dev; it creates
no source export or dependency override. The publication record in
[publishing.md](publishing.md) tracks the result.

## Reproducible consumer and package check

From the repository root on macOS with Flutter 3.47.4 / Dart 3.13.3 and Swift Package Manager:

```sh
python3 tool/check_macos_consumer.py --output build/macos-consumer/hosted
python3 tool/check_macos_consumer.py --candidate-facade --output build/macos-consumer/candidate
```

The first consumer resolves the production packages from pub.dev without
overrides. The second uses isolated exports of the desktop adapter, facade
and their siblings. It analyzes and tests the adapter and facade, then checks
both publish dry-run inventories for `pubspec_overrides.yaml` and `.env.tracer`. Each consumer
records its scope, resolved dependency sources and lockfile, builds release,
and verifies registration by receiving one error with user ID, key and breadcrumb
at a local receiver. No real DSN or plugin token is read.

The exact SDK pin produces one known Pub warning in `dart pub publish --dry-run`.
The check accepts only that warning; other warnings/errors fail. The pin is
intentional because SDK integrations and observer APIs are version-specific.
Both output directories contain logs, the consumer lockfile and the received event.
The candidate directory also contains a manifest of relative source paths and
SHA-256 hashes for each exported package.
