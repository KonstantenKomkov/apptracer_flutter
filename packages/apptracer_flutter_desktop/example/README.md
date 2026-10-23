# macOS desktop acceptance example

Separate dependency graph for `apptracer_flutter` + the optional official Sentry
SDK adapter. The existing Android/iOS/Web example is unchanged. macOS registration
selects `SentryDesktopTracer` automatically; registration itself does not start SDK
collection. Windows runner will be added and tested separately.

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

**This receiver is not Tracer.** Console delivery/grouping, native symbolication,
Windows runtime and complete consent/offline/restart acceptance remain separate
backlog checks. Native purge is not implemented yet: stop-and-clear reports
unsupported, and a fresh process may upload previously cached reports.
