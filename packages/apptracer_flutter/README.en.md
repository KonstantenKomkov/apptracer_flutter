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

Five minutes to the first event in the Tracer console. Every step below has a
fuller version further down.

**1. Create a project in the [Tracer console](https://apptracer.ru).** One per
platform. Each project issues **its own pair** — an `appToken` and a
`pluginToken`: an application on Android, iOS and web means three projects and
three pairs. Both values live under
**Настройки → Проект → API**.

**2. Wire the Tracer SDK into your build.** This package is a wrapper: it
neither ships the vendor's SDKs nor pulls them in — your application adds them.

### Android

In `android/settings.gradle.kts` — the plugin lives on Maven Central, not on
the Gradle Plugin Portal:

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("ru.ok.tracer") version "1.4.0" apply false
}
```

In `android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("ru.ok.tracer")
}

android {
    // The SDK reads appToken from a resource generated at build time. AGP 9
    // turns the feature off by default, and without it the SDK fails at runtime.
    buildFeatures {
        resValues = true
    }
}

tracer {
    create("defaultConfig") {
        appToken = "ANDROID_APP_TOKEN"
        pluginToken = providers.gradleProperty("androidPluginToken").orNull
        uploadMapping = true
        uploadNativeSymbols = true
    }
}

dependencies {
    implementation(platform("ru.ok.tracer:tracer-platform:1.4.0"))
    implementation("ru.ok.tracer:tracer-crash-report")
    // Optional, for native crashes:
    implementation("ru.ok.tracer:tracer-crash-report-native")
}
```

On Android the token comes from here, not from Dart: the SDK reads it from a
resource the Gradle plugin generates at build time. There is no runtime
alternative — which is why the plugin is required.

The two keys arrive differently for a reason. The plugin bakes the `appToken`
into the APK regardless, so there is nothing to hide — a literal is fine. The
`pluginToken` signs the upload of mappings and symbols, never reaches the
application, and does not belong in a repository.

Put it in `~/.gradle/gradle.properties`:

```properties
androidPluginToken=...
```

That file lives outside the repository and Gradle reads it on its own, so
nothing about launching changes: `flutter build` and the IDE's Run button both
see the value.

CI needs no file: the same property arrives as the environment variable
`ORG_GRADLE_PROJECT_androidPluginToken` — Gradle turns those into project
properties — or as `-PandroidPluginToken=…`. In GitHub Actions:

```yaml
- run: flutter build apk --release
  env:
    ORG_GRADLE_PROJECT_androidPluginToken: ${{ secrets.ANDROID_PLUGIN_TOKEN }}
```

Name the package's `Application` — one line in
`android/app/src/main/AndroidManifest.xml`:

```xml
<application android:name="ru.apptracer.flutter.TracerApplication" … >
```

It turns on the softer non-fatal rate limit, which matters more than it sounds:
Tracer's hard default is **8 non-fatals per session**
(`LIMIT_MAX_NON_FATALS_PER_SESSION`), and every Dart error this package reports
is a non-fatal — so that is the ceiling your app meets first, and it meets it
silently. The rate limit raises it to 10 per hour, and the vendor recommends
turning it on.

If you already have an `Application` of your own, subclass this one and add to
the list rather than replacing it:

```kotlin
class MyApplication : TracerApplication() {
    override val tracerConfiguration: List<TracerConfiguration>
        get() = super.tracerConfiguration + CoreTracerConfiguration.build {
            setDebugUpload(true)
        }
}
```

This cannot be the package's own default, unfortunately: the SDK reads its
configuration from the `Application` object and a plugin is not one.

Four more things that are easy to trip over:

* **`TracerOptions.appToken` is ignored on Android.** The token comes from the
  Gradle plugin. The plugin logs a warning if you pass one anyway rather than
  pretending it took effect.
* By default the SDK does not upload from debug builds. Enable it through
  `CoreTracerConfiguration.Builder.setDebugUpload` in an `Application` that
  implements `HasTracerConfiguration`.
* `Tracer.stopCollection()` calls the SDK's `Tracer.disable()`, which cannot be
  undone before the process restarts. That is deliberate; see
  [privacy.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md).
* `TracerOptions.environment` is ignored on Android too — the SDK takes it from
  the Gradle plugin, defaulting to the build variant name. Set it in the
  `tracer { }` block.

### iOS

In `ios/Podfile` — `OKTracer` lives in the vendor's own spec repository and
ships as a static `xcframework`, so both a source line and a change of linkage
are needed:

```ruby
source 'https://github.com/odnoklassniki/tracer-ios.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '13.0'

target 'Runner' do
  use_frameworks! :linkage => :static   # was: use_frameworks!
  # ...
end
```

Then `pod install`. The token is passed from Dart, one step below.

`OKTracer` vends a **static** `xcframework`, and CocoaPods refuses to let a
target using dynamic frameworks pull a static binary in transitively — hence the
change of linkage. Without it, `pod install` fails with *"The 'Pods-Runner' target has transitive
dependencies that include statically linked binaries"*. It is the same
requirement Firebase's static frameworks impose, and Flutter supports it.

Then `pod install`. The `appToken` **is** passed from Dart on iOS.

### Web

Nothing to add: the pure-Dart implementation is already inside the package. The
token is the JS project's `appToken`, passed one step below.

**3. Wrap the application's start.**

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';

void main() {
  Tracer.initialize(
    options: const TracerOptions(
      iosAppToken: 'IOS_APP_TOKEN',
      webAppToken: 'WEB_APP_TOKEN',
      release: '1.0.0',
      environment: 'prod',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

There is no Android field: its SDK reads the token from a resource the Gradle
plugin generates, and nothing from Dart overrides it. For a single platform the
shared `appToken` is enough — it is used wherever no specific one is set.

Keeping the keys in a file of their own next to the sources is exactly what
`flutterfire configure` does when it writes `lib/firebase_options.dart`. Nothing
is needed here for that beyond the convention:

```dart
// lib/tracer_options.dart
import 'package:apptracer_flutter/apptracer_flutter.dart';

const TracerOptions tracerOptions = TracerOptions(
  iosAppToken: 'IOS_APP_TOKEN',
  webAppToken: 'WEB_APP_TOKEN',
  release: '1.0.0',
);
```

```dart
Tracer.initialize(options: tracerOptions, appRunner: ...);
```

The Android token cannot move there: the Gradle plugin needs it at build time,
before any Dart exists.

**The `appToken` is not a secret**, and there is little point hiding it: the
Gradle plugin bakes it into the APK — it sits in `resources.arsc` and
`classes.dex`, unzip one and see — and on web it is in the JavaScript bundle
anyway. It identifies the project rather than granting access to it. So use
whichever of these suits you:

* a string in the code, or in a settings file next to your sources — the same
  shape as Firebase's `firebase_options.dart`;
* `--dart-define=TRACER_APP_TOKEN=…` together with
  `appToken: String.fromEnvironment('TRACER_APP_TOKEN')`, if you would rather
  it stayed out of git;
* from your own configuration at runtime — `TracerOptions` takes an ordinary
  string and does not care where you got it.

**The `pluginToken` is a secret.** It signs the upload of mappings and symbols,
only the build needs it, and it never reaches the application: it is not in the
APK. It belongs in the build environment and in CI secrets, not in a
repository.

Everything thrown from here on — uncaught exceptions, failures inside `build()`,
asynchronous errors nobody awaited — reaches Tracer on its own. There is nothing
else to call.

**4. Confirm it is alive.** Put one line behind a button and press it:

```dart
onPressed: () => throw StateError('apptracer_flutter check'),
```

An event should appear in the console. The title differs by platform, and that
is expected: on Android it reads
`DartError: StateError: apptracer_flutter check`, while on iOS the console
always prefixes its own rendering of the top native frame, so it reads
`+ 0 - StateError: apptracer_flutter check`. The readable Dart stack trace is
in the log tab either way.

### If nothing arrives

It is almost always one of four things:

* **The platform setup was skipped.** At startup the package prints a line
  saying it is disabled and why, and `Tracer.isEnabled` is `false` at that
  moment. Read the log first.
* **It is a debug build.** The native SDK sends nothing from debug builds by
  default, on either platform. Test on release, or turn on `setDebugUpload`
  (Android, below).
* **Android: `resValues = true` is missing.** AGP 9 turns the feature off by
  default, and the SDK reads `appToken` out of exactly that generated resource
  — without it, it fails at runtime.
* **Android: the token was passed in `TracerOptions`.** It is ignored there; on
  Android the token comes only from the `tracer { }` block in Gradle.
* **iOS or web: the `appToken` arrived empty.** Usually the `--dart-define`
  route with the flag missing from the build: without it
  `String.fromEnvironment` returns an empty string. The package says plainly
  that no `appToken` was given and stays disabled.

### Where to go next

* [Usage](#usage) — reporting by hand, breadcrumbs, custom keys.
* [Consent](#consent) — how to collect nothing until the user agrees.
* [What data is transmitted](#what-data-is-transmitted) — the full list,
  including what the native SDK adds on its own.
* [Release builds with `--split-debug-info`](#release-builds-with---split-debug-info) —
  what happens to a stack trace and how to read it back.

## Why this exists

The native Tracer SDKs cannot see Dart errors.

The Android SDK installs a `Thread.UncaughtExceptionHandler`, a native signal
handler and an ANR watchdog. An unhandled Dart exception trips none of them: it
does not terminate the process and it never enters the JVM. Flutter catches it
inside Dart, through `FlutterError.onError`,
`PlatformDispatcher.instance.onError`, or the error handler of a guarded zone.
The same holds on iOS.

For a Flutter application that is most of the errors. Install the Tracer SDK on
its own and you get native crashes and ANRs — and a suspiciously quiet
dashboard, because the exceptions your users actually hit never arrive.

This package hooks those three Dart entry points and forwards what it finds to
the native SDK, which keeps handling native crashes, ANRs and the crash-free
metric itself.

## How this differs from firebase_crashlytics

A fair question: Crashlytics is free, official, and does the same job.

| | apptracer_flutter | firebase_crashlytics |
|---|---|---|
| Who makes it | an independent wrapper, unaffiliated with VK or OK.TECH | Google, the official plugin |
| Platforms | Android, iOS, web | Android, iOS, macOS |
| Where reports go | Tracer's servers (VK / OK.TECH) | Google's infrastructure |
| Dart error capture | `FlutterError.onError`, `PlatformDispatcher.onError`, a guarded zone | `FlutterError.onError`, `PlatformDispatcher.onError` |
| Obfuscated Dart | by hand: `flutter symbolize` against the archived symbol file | `firebase crashlytics:symbols:upload` on Android, automatic on Apple |

**About the data.** Little can be said with certainty, and it is better said
without legal phrasing: Crashlytics sends reports into Google's infrastructure,
Tracer into its own. If keeping data inside a particular jurisdiction matters
to you — which for Russian applications is usually the reason Tracer is on the
table at all — that is the difference. A crash log is not anonymous by nature,
either: what makes it personal data is what you put in it — `userId`, custom
keys, breadcrumbs, the exception message. Exactly what leaves the device from
this package, and what the vendor's SDK adds on its own, is listed in
[privacy.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md). Whether that satisfies your
jurisdiction's rules is a question for your lawyer, not for a README.

**About Dart symbols, honestly.** Crashlytics is plainly better here. It reads
such a release by itself; here that is manual work. Tracer has no channel for
Dart debug files — the vendor confirmed as much on 2026-08-27 — and the native
channel accepts the upload but never applies it, because the reporter records
`libapp.so` with a zero build id. Measured 2026-08-27, written up in [symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md).
Until the vendor fixes that, there is one working route: archive the build's
symbol file and decode traces with `flutter symbolize`.

## What you get beyond Dart errors

Dart errors are this package's job and arrive the same from every platform.
What differs is everything else, because the vendor's native SDK does that
part:

* **Android** — native crashes and ANRs. ANRs only from Android 11: `AnrReporter`
  in `tracer-crash-report` 1.4.0 builds its report from `ApplicationExitInfo`,
  which arrived in API 30, and below that `setSendAnr(true)` buys nothing.
* **iOS** — native crashes and the hang counter.
* **Web** — Dart errors only; there is no such thing as a native crash there.

Desktop and Aurora are not supported and are not among the package's platforms.
Why is in [Desktop and Aurora](#desktop-and-aurora).

On a platform with no implementation the package is inert: `isEnabled` is
`false`, one diagnostic line is printed, nothing throws, and your app still
starts. Full details in [platform-matrix.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md).

## Desktop and Aurora

This release does **not support** them. Neither has a Flutter-facing Tracer
SDK, and no build for either has ever been run against a
real project. The transport can be registered there and Dart errors would
probably arrive — "probably" being the entire claim:

```yaml
dependencies:
  apptracer_flutter_http: ^0.1.0
```

```dart
import 'package:apptracer_flutter_http/apptracer_flutter_http.dart';

TracerPlatform.instance = TracerHttpTracer(
  facts: PlatformClientFacts(),
  sdkVersion: '0.1.0',
);
```

## Usage

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';

void main() {
  Tracer.initialize(
    options: const TracerOptions(
      appToken: String.fromEnvironment('TRACER_APP_TOKEN'), // iOS and web
      // dsn is only for the Sentry transport, i.e. the unsupported platforms
      environment: 'prod',
      release: '1.0.0',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

`appRunner` runs **exactly once, in every scenario** — a normal start, a start
with collection disabled by policy, a platform SDK that throws while starting,
and a platform with no implementation at all. An error reporter that can stop an
application from starting is worse than no error reporter.

Reporting a handled error:

```dart
try {
  await repository.load();
} catch (error, stackTrace) {
  await Tracer.recordError(
    error,
    stackTrace,
    severity: TracerSeverity.warning,
    issueKey: 'ORDERS-LOAD',                       // overrides Tracer grouping
    customKeys: {'endpoint': '/orders'},
  );
}
```

Breadcrumbs and keys:

```dart
Tracer.log('user tapped checkout', category: 'ui');
await Tracer.setCustomKey(key: 'checkout_step', value: '3');
await Tracer.removeCustomKey('checkout_step');
```

Breadcrumbs are buffered in Dart *and* mirrored into the native log buffer as
they happen, so a native crash — which the Dart side never sees — still arrives
with the trail attached.

### Consent

```dart
// Before the first frame:
Tracer.initialize(
  options: TracerOptions(isCollectionEnabled: consent.isGranted),
  appRunner: () => runApp(const MyApp()),
);

// Withdrawn mid-session:
await Tracer.stopCollection();
```

`stopCollection` removes the Dart error handlers and restores whatever was
installed before — including your own. It only restores when the currently
installed handler is still the one this package installed; if something else
took over afterwards, it says so and leaves that handler alone rather than
deleting a third party's work.

### Redacting

```dart
TracerOptions(
  beforeSend: (event) => event.message.contains('@')
      ? event.copyWith(message: '<redacted>')
      : event,
  beforeBreadcrumb: (crumb) => crumb.category == 'auth' ? null : crumb,
)
```

Return `null` to drop. A hook that throws is logged and ignored, and the
original event is still sent.

### Very large stack traces

The verbatim trace written to the platform log is capped at 8 KiB by default,
and the parsed frames at 128.

Both defaults exist because Android's log buffer is a **circular** 64 KiB
buffer: everything written to it evicts something older. A pathological Dart
trace — a `StackOverflowError`, a deep async chain — runs to hundreds of
kilobytes and would flush the whole breadcrumb trail out of the buffer, so the
report would arrive with a stack trace and no context at all.

Truncation keeps the beginning of the trace, where the `build_id` header and
the frames nearest the throw are, and says how many lines it dropped. Raise or
disable it if you need more:

```dart
TracerOptions(
  maxRawStackTraceLogBytes: 32768,  // 0 = no limit
  maxStackFrames: 256,              // 0 = no limit
)
```

### Severity of automatically captured errors

Errors caught through `FlutterError.onError`, `PlatformDispatcher.onError` and
the guarded zone are reported as `error`, not `fatal`. None of them terminate
the process — that is the whole reason the native SDKs cannot see them — and a
fatal report counts against the crash-free metric on Android and iOS, so marking
them fatal would report crashes that never happened.

If your team has deliberately decided otherwise:

```dart
TracerOptions(reportUnhandledErrorsAsFatal: true)
```

## What data is transmitted

This package adds **no personal data of its own**: no install id, no device id,
no user id, no automatic context. Everything it sends is a property of the error
or something you handed it explicitly.

The native SDKs are a separate matter — the Android SDK collects device model,
manufacturer, ABI, OS version, mobile operator and installer package on its own,
whether or not this package is installed. The full table, and how to constrain
it, is in [privacy.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md).

### Grouping

When the caller supplies no `issueKey`, the package synthesises one from the
error type and the innermost named frame, bounded to 32 characters.

This is not decoration. On Android, Tracer keys a group on the top frame's class
and method and nothing else — measured against a live project on 2026-08-26,
where a `StateError` and a `TimeoutException` thrown from two closures inside
one `build` landed in the same group. In a Flutter application most handlers are
exactly such closures. iOS gets there by a different route with the same result:
a Dart stack trace carries no native addresses, so there is nothing to group on
at all.

Neither the file nor the line number goes into the key: Tracer ignores them by
design, so that editing code does not scatter one issue across several groups,
and the synthetic key preserves that. An `issueKey` you pass to `recordError`
always wins.

## Release builds with `--split-debug-info`

If you build with `--split-debug-info` — with or without `--obfuscate`, measured
2026-08-27 — Dart stack traces become addresses:

```
build_id: 'b71885097a7ebc4d1ab80642f606c4be'
#00 abs 0000007938a1c2f0 virt 00000000002cc2f0
```

The package always sends the **verbatim** trace, header included, so it stays
decodable:

```
flutter symbolize -d build/symbols/app.android-arm64.symbols -i trace.txt
```

**Tracer has no upload channel for Dart `--split-debug-info` files** — the
vendor confirmed as much on 2026-08-27 — so decoding stays a manual step. Read
[symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md)
before you ship such a build — it explains what does and does not work, and how
to avoid finding out the hard way.

## Maturity

Version `0.1.0`. The Dart-side behaviour is unit-tested in detail; delivery has
not yet been confirmed against a live Tracer project, because that needs
credentials this repository does not have.
[status.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/status.md)
lists exactly what is proven and what is not. The version stays below `1.0.0`
until a real project has confirmed end-to-end delivery on each platform.

## Packages

| Package | Purpose |
|---|---|
| `apptracer_flutter` | what applications depend on |
| `apptracer_flutter_platform_interface` | models, stack-trace parser, platform contract |
| `apptracer_flutter_android` | Kotlin bridge to `ru.ok.tracer` |
| `apptracer_flutter_ios` | Swift bridge to `OKTracer` |
| `apptracer_flutter_web` | web implementation |
| `apptracer_flutter_http` | pure-Dart Sentry-protocol transport |

## License

MIT. The vendor SDKs are licensed separately; see
[legal.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/legal.md).
