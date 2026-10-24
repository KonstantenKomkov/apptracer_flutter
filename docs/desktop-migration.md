# Desktop installation and migration

The optional `apptracer_flutter_desktop` package is experimental and unpublished.
The accepted macOS scope is recorded in
[macos-lifecycle-acceptance.md](macos-lifecycle-acceptance.md); Ubuntu 22.04.5
x86_64 VM evidence is in [linux-preparation.md](linux-preparation.md).
Windows/Aurora work proceeds separately; their pending checks do not become
accepted by passing this macOS procedure.

## External application

Use the published facade and a pinned repository revision containing the adapter:

```yaml
dependencies:
  flutter:
    sdk: flutter
  apptracer_flutter: ^0.2.1
  apptracer_flutter_desktop:
    git:
      url: https://github.com/KonstantenKomkov/apptracer_flutter.git
      ref: YOUR_REVIEWED_COMMIT_SHA
      path: packages/apptracer_flutter_desktop
flutter:
  config:
    enable-swift-package-manager: false
```

Replace the revision placeholder with the commit you have reviewed. A path
dependency to an isolated adapter copy is also supported. Do not copy the
repository's `pubspec_overrides.yaml` into the app: its sibling paths are for
repository development. Pub ignores overrides declared by dependencies;
the consumer must resolve public siblings from pub.dev
([Dart dependency rules](https://dart.dev/tools/pub/dependencies#dependency-overrides)).

Use CocoaPods, set `platform :osx, '12.0'` in the macOS Podfile and set the
Runner deployment target to at least 12.0. Enable
`com.apple.security.network.client` in the sandboxed release entitlements.
The example's [Podfile](../packages/apptracer_flutter_desktop/example/macos/Podfile)
is a reference. Swift Package Manager is not supported by this bridge.

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

The current hosted facade 0.2.1 predates the stable `FlutterError` type-name fix
under obfuscation. For that fix, use the reviewed facade source as a second
path/git dependency until facade 0.2.2 is published. Public siblings still
resolve from pub.dev; do not use monorepo overrides. Source-frame decoding
belongs to the adapter and is separate from that facade fix.

Run the external-consumer check from this repository on Ubuntu:

```sh
xvfb-run -a python3 tool/check_linux_consumer.py --output build/ubuntu-consumer-hosted
xvfb-run -a python3 tool/check_linux_consumer.py --candidate-facade \
  --output build/ubuntu-consumer-candidate
```

It validates staged publish candidates, builds a newly generated release app,
relocates it into a path with spaces/Cyrillic, checks automatic registration,
filtered data, deduplication, exact-build source frames and stop/clear using a
loopback receiver. `--candidate-facade` stages facade 0.2.2 without changing
repository versions or publishing. The exported `consumer-bundle.tar.gz` can
also be checked on a clean VM with `--bundle <extracted-bundle>`.

## Moving from the manual transport

1. Remove `apptracer_flutter_sentry`, its `SentryProtocolTracer()` registration
   and any separately initialized Sentry SDK. Add the optional desktop adapter.
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

## Windows consumer

Use the optional desktop path/git dependency alongside the facade. Before
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
0.16.6 checkout. Both variants resolve siblings from pub.dev without overrides;
the candidate temporarily stages facade 0.2.2 for its obfuscated FlutterError
name fix. Hosted 0.2.1 delivers correctly but retains the old name limitation.
The harness performs package dry-runs, builds obfuscated release, relocates it,
restricts PATH to Windows/System32 and verifies filtering/deduplication/source
frames/clear. This does not replace clean-machine testing.
[Local results and publication boundary](windows-local-acceptance.md).

Publication is deferred by the maintainer (2026-10-24). When both versions are
published, repeat the Windows consumer check with hosted packages only:

```powershell
python -X utf8 tool/check_windows_consumer.py --hosted-desktop 0.1.0-dev.1 --facade-version 0.2.2 --output build/windows-consumer-published --dump-syms D:\Tools\Symbols\dump-syms\dump_syms.exe
```

This mode checks that every Tracer dependency resolves from pub.dev; it creates
no source export or dependency override. The command is prepared for the later
release and has not been represented as a successful hosted desktop check.

## Reproducible consumer and package check

From the repository root on macOS with Flutter 3.47.4 / Dart 3.13.3 and CocoaPods:

```sh
python3 tool/check_macos_consumer.py --output build/macos-consumer
```

This exports only tracked desktop package files into a temporary directory
outside the repository, removes development overrides, and validates a staged
publish candidate. It then creates a new Flutter macOS app with exactly one
path dependency (that export) and hosted public sibling dependencies. It checks
the resolved sources, analyzes and builds release, and verifies automatic
plugin registration by receiving one error with user ID, key and breadcrumb
at a local receiver. No real DSN or plugin token is read.

The repository retains `publish_to: none`; only the temporary copy permits
`dart pub publish --dry-run`. The exact SDK pin produces one known Pub warning.
The check accepts only that warning; other warnings/errors fail. The pin is
intentional because SDK integrations and observer APIs are version-specific.
Logs, the dependency lockfile, export file list and event are written under
the output directory. This checks an isolated path consumer, not a published
desktop version or a Git install. Actual publication and a hosted desktop
consumer remain separate release steps.
