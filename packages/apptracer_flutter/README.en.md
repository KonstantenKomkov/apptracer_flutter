# apptracer_flutter

Unofficial Flutter integration with [Tracer](https://apptracer.ru), the
error-monitoring service by OK.TECH / VK.

> **Not an official SDK.** This package is not affiliated with, endorsed by, or
> supported by VK or OK.TECH. It is an independent wrapper around the vendor's
> public SDKs and it does not redistribute them. Do not report problems with it
> to Tracer support — [open an issue here](https://github.com/KonstantenKomkov/apptracer_flutter/issues)
> instead.

Русская версия: [README.md](README.md).

## Quick start

**1. Create a project in the [Tracer console](https://apptracer.ru).** Use a
separate project for each platform. Under **Settings → Project → API**, copy the
`appToken` for events and the `pluginToken` for symbols.

**2. Configure your platform.**

### Android

Follow the [full Android guide](../../docs/android-guide.en.md) for the Tracer
BOM and Gradle plugin, repositories, `resValues = true`, tokens and native
crashes. `TracerOptions.appToken` and `TracerOptions.environment` are ignored on
Android.

#### Android tombstones (SDK 1.5.2)

Experimental tombstones are off by default. See
[debug and native crashes](../../docs/android-guide.en.md#debug-and-native-crashes)
for setup and limitations.

### Upgrading to Android SDK 1.6.2

Use `apptracer_flutter ^1.2.1` (Android adapter `^0.4.1`) and the
[Android guide](../../docs/android-guide.en.md). Historical notes and known
limitations are in the [release history](../../docs/release-history.md#android-sdk-162-migration).

### iOS

Choose Swift Package Manager or CocoaPods in the
[iOS guide](../apptracer_flutter_ios/README.en.md#setup). It also covers
`dSYM` uploads and `pluginToken`. `appToken` is passed from Dart.

### Web

No additional implementation is needed: it is already inside the package. Pass
the JS project's `appToken` from Dart. Offline queueing, retries, limits and
duplicate risks are described in the
[web protocol](../../docs/web-protocol.md#delivery-reliability). Source maps are
covered there and in [symbolication.md](../../docs/symbolication.md).

### Desktop (optional)

For Windows, macOS and Ubuntu Linux, add `apptracer_flutter_desktop ^1.0.0` and
configure the Tracer project's Sentry DSN using the
[desktop guide](../../docs/desktop-migration.md). The facade alone does not add
a desktop backend.

**3. Wrap the application's start.**

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';

void main() {
  Tracer.initialize(
    options: const TracerOptions(
      iosAppToken: 'IOS_APP_TOKEN',
      webAppToken: 'WEB_APP_TOKEN',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

`appRunner` runs exactly once, including initialization failure and disabled
collection. For a single platform, the shared `appToken` is enough. On Android,
the token comes only from Gradle.

**4. Send a test event.**

```dart
onPressed: () => throw StateError('apptracer_flutter check'),
```

Check the event in the Tracer console. The readable Dart stack is in the log
tab. For handled errors, use `Tracer.recordError` as shown in the
[context guide](../../docs/filtering.en.md).

### If nothing arrives

Check the startup log and `Tracer.isEnabled` first. Then:

- Android: the Gradle plugin and `resValues = true` are enabled and the token is
  set in `tracer { }`.
- iOS/web: `appToken` is set, for example through `--dart-define`.
- Test on release; debug uploads are off by default.
- In deferred mode, consent was followed by an explicit `startCollection`.

See the [platform matrix](../../docs/platform-matrix.md) and the
[consent guide](../../docs/native-collection-consent.md).

## Usage

- [Filtering, breadcrumbs and custom context](../../docs/filtering.en.md).
- [Consent, pause/resume and stop/clear](../../docs/native-collection-consent.md).
- [Transmitted data and privacy](../../docs/privacy.md).
- [Symbolication and large traces](../../docs/symbolication.md).
- [Current platform versions and limitations](../../docs/platform-matrix.md).

### Consent

Use deferred initialization before consent, `Tracer.startCollection()` after it,
and `Tracer.stopAndClearCollection()` on logout. The exact contract and cleanup
limits are in [native-collection-consent.md](../../docs/native-collection-consent.md).

### Redacting

`beforeSend` and `beforeBreadcrumb` can change or drop data before it reaches
the platform. Examples and large-trace limits are in
[filtering.en.md](../../docs/filtering.en.md).

### Very large stack traces

The verbatim trace is capped at 8 KiB by default and parsed frames at 128. See
[large stack traces](../../docs/filtering.en.md#large-stack-traces).

### Severity of automatically captured errors

Automatically captured errors are reported as `error`, not `fatal`, because the
process does not terminate. Set `reportUnhandledErrorsAsFatal: true` only for a
deliberate different policy.

## Why this exists

The native Tracer SDKs cannot see Dart errors. The package captures them through
`FlutterError.onError`, `PlatformDispatcher.instance.onError` and guarded zones
and forwards them to the native SDK, which keeps handling native crashes, ANRs
and crash-free metrics.

## Comparison with Firebase Crashlytics

Both packages capture Dart errors. Tracer uses VK / OK.TECH SDKs and ingest;
Firebase uses Google's SDKs and ingest. Data and privacy limitations are in
[privacy.md](../../docs/privacy.md).

## What you get beyond Dart errors

Native crashes and ANRs/hangs are handled by the platform SDK. Current
capabilities and limitations live only in
[platform-matrix.md](../../docs/platform-matrix.md).

## What data is transmitted

On Android and iOS the package adds no personal data of its own. Web adds a
`deviceId` and browser context; native SDKs collect their own metadata. See
[privacy.md](../../docs/privacy.md).

### Grouping

An explicit `issueKey` wins. Otherwise the key is derived from the error type
and innermost named frame, excluding file and line number.

## Release builds with `--split-debug-info`

The package preserves the verbatim trace and `build_id`. Symbols must come from
the exact build; manual decoding with `flutter symbolize` is described in
[symbolication.md](../../docs/symbolication.md).

## Runtime APIs in apptracer_flutter 1.2.0

Release-specific pause/resume and diagnostic APIs moved to the
[release history](../../docs/release-history.md#apptracer_flutter-120-runtime-apis).
Current lifecycle contracts are in [native-collection-consent.md](../../docs/native-collection-consent.md).

## License

MIT. The vendor SDKs are licensed separately; see
[legal.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/legal.md).
