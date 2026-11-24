# apptracer_flutter_desktop

Optional adapter for reporting Dart errors and native crashes to Tracer on macOS, Windows and Ubuntu. The `apptracer_flutter` facade installs the error handlers. The adapter sends reports through the official Sentry Flutter SDK using your Tracer project's DSN.

[Русский](README.md)

## Quick start

1. Install the facade and adapter from your desktop application's directory. Adapter 2.0.0 requires Flutter 3.44 or later and Dart 3.12 or later.

   ```sh
   flutter pub add apptracer_flutter apptracer_flutter_desktop
   ```

2. Configure the build for your platform.

   | Platform | Setup |
   |---|---|
   | macOS arm64 | Enable Swift Package Manager, set the Runner deployment target to macOS 12.0 or later and allow outgoing connections in the release entitlements. [macOS setup](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#external-application) |
   | Windows 11 x64 | Set `$env:SENTRY_NATIVE_BACKEND = 'native'` in PowerShell before building. Ship the entire Release directory with its DLLs and crash handler. [Windows build](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#windows-consumer) |
   | Ubuntu 22.04.5 x86_64 (X11) | Set `SENTRY_NATIVE_BACKEND=native` and configure CMake to install an executable `lib/sentry-crash` in the bundle. [CMake and packaging](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#ubuntu-linux-consumer) |

3. Pass the HTTPS DSN from the Tracer project for your target platform. The adapter registers automatically.

   ```dart
   import 'package:apptracer_flutter/apptracer_flutter.dart';
   import 'package:flutter/material.dart';

   Future<void> main() async {
     await Tracer.initialize(
       options: const TracerOptions(dsn: String.fromEnvironment('TRACER_DSN')),
       appRunner: () => runApp(const MyApp()),
     );
   }
   ```

4. Run with the DSN. On macOS, use the command below. On Windows or Ubuntu, select the `windows` or `linux` device.

   ```sh
   flutter run -d macos --release --dart-define=TRACER_DSN=YOUR_PROJECT_DSN
   ```

   Call `await Tracer.recordError(StateError('desktop check'), StackTrace.current)` from a button and open the event in your Tracer project.

## Consent and delivery

For deferred collection, set `TracerOptions.nativeInitialization` to `TracerNativeInitialization.deferred`. Call `Tracer.startCollection()` after consent and `Tracer.stopAndClearCollection()` on withdrawal. After stopping an active native SDK, restart the process to collect again. On an ordinary restart, replay requires `preservePreviousReports: true`. On macOS an HTTP 5xx response can cause an event to be lost. [Lifecycle and delivery limits](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#sentry-upgrades)

The adapter initializes Sentry. Use `Tracer` to report events. The `beforeSend` filter applies to Dart events. A native crash report can include previously recorded keys, logs and user IDs. [Data and privacy](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md)

If mobile and desktop builds share a `pubspec.yaml`, the `sentry_flutter` dependency also brings native SDKs into Android and iOS. Use a separate desktop application to keep those dependency sets independent.

## Example and guides

- [Example for all three platforms](example/README.md)
- [Platform matrix and symbol verification](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md#summary)
- [Migration from the old transport](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/desktop-migration.md#moving-from-the-manual-transport)
- [Separate Flutter Aurora adapter](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/aurora-release.md)
