# Windows/macOS/Ubuntu desktop acceptance example

Ubuntu 22.04 x86_64 uses `TRACER_LINUX_SENTRY_DSN` and automatic registration.
From the repository root run `bash tool/build_linux_desktop.sh`; launch the entire
`build/linux/x64/release/bundle` from this example's build directory. The helper
selects `SENTRY_NATIVE_BACKEND=native` and bundles executable `lib/sentry-crash`.
It also creates native Breakpad maps in `bundle/lib/symbols` for automatic source
resolution inside the crash daemon. Keep this directory with the bundle; Dart
AOT split-debug-info remains a separate artifact under `build/symbols/dart`.
The helper also generates a compact Dart source map in `lib/apptracer-dart-symbols`
for automatic file/line display. This exposes function names and file paths;
set `TRACER_BUNDLE_DART_SYMBOLS=0` to omit it when preserving obfuscation matters.
Dependencies,
Xvfb probes, WSL2/clean Ubuntu VM results and outstanding acceptance are in
[linux-preparation.md](../../../docs/linux-preparation.md).

Separate dependency graph for `apptracer_flutter` + the optional official Sentry
SDK adapter. The existing Android/iOS/Web example is unchanged. Windows/macOS/Linux registration
selects `SentryDesktopTracer` automatically; registration itself does not start SDK
collection. Windows x64 release build, Dart/native loopback delivery and native
queue recovery after HTTP 503 passed in CI. Stop/clear and live Tracer remain pending.

## Build and launch

Run from this directory with Flutter 3.47.4 / Xcode 27 (the initial local toolchain):

```sh
flutter pub get
env -u GEM_HOME -u GEM_PATH flutter build macos --release
```

The per-project Flutter configuration disables Swift Package Manager for this
example; Sentry Flutter 9.30.1 uses CocoaPods. Unsetting the Ruby gem variables fixes
the mixed RVM/Homebrew environment on the development machine; it does not modify
system Ruby. The runner deployment target is macOS 12.0; this is a build setting,
not a claim of runtime testing on macOS 12.

Launch the executable in
`build/macos/Build/Products/Release/apptracer_desktop_example.app/Contents/MacOS/`.
It reads `TRACER_MACOS_SENTRY_DSN` from its process environment, or from a Dart define
of the same name. Without a valid DSN, the app starts with collection disabled.
Do not pass an entire shared secrets file to `--dart-define-from-file`: it may
contain symbol plugin tokens that do not belong in an application.

The UI provides handled Dart error, FlutterError, unhandled async error, native
crash with confirmation, and start/stop/clear controls. Native crash terminates
only this example; restart it to test upload. The release sandbox grants outbound
network access and uses the SDK's normal sandbox container for persistent data.

This acceptance example opts into `preservePreviousReports: true` to recover native
crashes after restart. Set `TRACER_PRESERVE_REPORTS=false` to discard old reports.
The library API default remains false. On macOS, stop revokes replay regardless of
this flag. Windows revocation and cleanup are not implemented; starting with this
flag set to false returns `unsupported` before SDK initialization.

## Local SDK transport acceptance

From the repository root, after building the app:

```sh
python3 tool/check_macos_desktop.py \
  --app packages/apptracer_flutter_desktop/example/build/macos/Build/Products/Release/apptracer_desktop_example.app \
  --scenario smoke --output build/macos-acceptance/smoke.json
```

Other scenarios: `disabled`, `deferred`, `native-crash`. Each invocation starts its
own local receiver, supplies a dummy loopback DSN, copies the app to a temporary
path with spaces/Cyrillic characters and launches it directly outside the checkout.
It stops only its own process. The native-crash scenario deliberately terminates
and restarts that process. Reports include the synthetic test events and local OS
metadata; they are generated under ignored `build/` directories.

`smoke` requires exactly one event for each Dart/Flutter/async error, SDK event
items only, the expected run key, user and breadcrumb. Disabled/deferred scenarios
require a ready app and no received requests during the observation window.
This is a bounded local transport test, not proof of all native lifecycle cases.

For the macOS lifecycle checks:

```sh
python3 tool/check_macos_lifecycle.py \
  --app packages/apptracer_flutter_desktop/example/build/macos/Build/Products/Release/apptracer_desktop_example.app \
  --output build/macos-acceptance/lifecycle.json
```

The opt-in `lifecycle` scenario reads commands from inherited stdin; it opens no
control listener. The driver checks offline/hold responses, stop/clear, persisted
files, account change, normal and crash restarts, and default report disposal.
Run acceptance scripts sequentially: this example has one shared sandbox/cache.
They deliberately create synthetic crash reports in the example process.

**This receiver is not Tracer.** Console delivery/grouping and Windows runtime
remain separate checks. Native macOS server symbolication is unsupported in the
tested integration. Local macOS stop/clear results and their limits are documented
in [macOS lifecycle acceptance](../../../docs/macos-lifecycle-acceptance.md).

## Windows x64

Use Flutter 3.47.4 and Visual Studio with Desktop development with C++.
From this example directory:

```powershell
../../../tool/build_windows_desktop.ps1
$env:TRACER_WINDOWS_SENTRY_DSN = '<DSN of the Windows Tracer project>'
.\build\windows\x64\runner\Release\apptracer_desktop_example.exe
```

Copy the entire `Release` directory when moving to another machine, including
Sentry, Flutter, Crashpad and data files. Native runner PDBs from the same build
are retained under `build/symbols/native`. This does not upload them or establish
Tracer symbolication. No plugin token is compiled into the application.

Run `tool/check_windows_desktop.py` from the repository root, with `--app` pointing
to that Release directory and `--scenario disabled`, `deferred` or `smoke`.
It uses a dummy loopback DSN and relocates the complete bundle to a temporary
path with spaces/Cyrillic. It closes only its own process tree.
[Commands and remaining acceptance](../../../docs/windows-preparation.md).
