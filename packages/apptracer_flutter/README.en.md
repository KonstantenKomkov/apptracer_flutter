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
That is where the difference between platforms comes from, and where the token
comes from too. Not skippable: without it the package starts, prints that it is
disabled, and sends nothing.

| Platform | What to add | Where the token comes from | In full |
|---|---|---|---|
| Android | the `ru.ok.tracer` Gradle plugin and the SDK dependencies | the `tracer { }` block in Gradle | [Android](#android) |
| iOS | a `source` line in the `Podfile` and static linkage | `TracerOptions` | [iOS](#ios) |
| Web | nothing: the pure-Dart implementation is already in the package | `TracerOptions` | [Web](#web-and-other-platforms) |

**3. Wrap the application's start.**

```dart
import 'package:apptracer_flutter/apptracer_flutter.dart';

void main() {
  Tracer.initialize(
    options: const TracerOptions(
      // The iOS or web project's appToken. On Android it comes from the
      // Gradle plugin and this field is ignored.
      appToken: 'your-app-token',
      release: '1.0.0',
      environment: 'prod',
    ),
    appRunner: () => runApp(const MyApp()),
  );
}
```

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
* [Obfuscated release builds](#obfuscated-release-builds) — what happens to a
  stack trace and how to read it back.

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

**About obfuscation, honestly.** Crashlytics is plainly better here. It reads an
obfuscated release by itself; here that is manual work. Tracer has a channel for
Dart symbols and the upload goes through, but the symbols are never applied,
because the native reporter records `libapp.so` with a zero build id. Measured
2026-08-27, written up in [symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md).
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
Why is at the end of the [Web](#web-and-other-platforms) section.

On a platform with no implementation the package is inert: `isEnabled` is
`false`, one diagnostic line is printed, nothing throws, and your app still
starts. Full details in [platform-matrix.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md).

## Platform setup

Step 2 of the quick start, in full. Not optional: without it the package starts,
reports that it is disabled, and sends nothing.

### Android

The Tracer Android SDK reads its `appToken` from a resource generated at build
time, so the Gradle plugin has to be applied. There is no runtime alternative.

`android/settings.gradle.kts` — the plugin lives on Maven Central, not on the
Gradle Plugin Portal:

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

`android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("ru.ok.tracer")
}

android {
    buildFeatures {
        // Tracer relies on resources generated at build time. AGP 9 turns this
        // off by default, and without it the SDK fails at runtime.
        resValues = true
    }
}

tracer {
    create("defaultConfig") {
        // Not System.getenv: this runs in the Gradle daemon, which inherits the
        // environment of the shell that started it and is reused across builds,
        // so a token exported afterwards stays invisible.
        appToken = providers.environmentVariable("TRACER_APP_TOKEN").orNull
        pluginToken = providers.environmentVariable("TRACER_PLUGIN_TOKEN").orNull
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

Read the `pluginToken` from the environment: it never reaches the application
and stays a secret, and a secret committed to a repository is a secret that has
leaked. There is no need to be stricter with the `appToken` than suits you —
the plugin bakes it into the APK regardless.

The environment itself is your business. Locally a file outside the repository
is usually enough:

```sh
# ~/.tracer-env — outside any git repository, chmod 600
export TRACER_ANDROID_APP_TOKEN=...
export TRACER_ANDROID_PLUGIN_TOKEN=...
# If the application also ships on iOS or web, those are separate projects with
# separate pairs, and mixing them up is easy:
export TRACER_IOS_APP_TOKEN=...
export TRACER_IOS_PLUGIN_TOKEN=...
```

```sh
source ~/.tracer-env && \
  TRACER_APP_TOKEN=$TRACER_ANDROID_APP_TOKEN \
  TRACER_PLUGIN_TOKEN=$TRACER_ANDROID_PLUGIN_TOKEN \
  flutter build apk --release
```

In CI, through the build system's secrets — in GitHub Actions:

```yaml
- run: flutter build apk --release
  env:
    TRACER_APP_TOKEN: ${{ secrets.TRACER_ANDROID_APP_TOKEN }}
    TRACER_PLUGIN_TOKEN: ${{ secrets.TRACER_ANDROID_PLUGIN_TOKEN }}
```

Turn on the softer non-fatal rate limit. Tracer's hard default is **8
non-fatals per session** (`LIMIT_MAX_NON_FATALS_PER_SESSION`), and every Dart
error this package reports is a non-fatal, so that ceiling is the one your app
will meet first. Enabling the rate limit raises it to 10 per hour and is what
the vendor recommends:

```kotlin
class MyApplication : Application(), HasTracerConfiguration {
    override val tracerConfiguration: List<TracerConfiguration>
        get() = listOf(
            CrashReportConfiguration.build {
                setExperimentalNonFatalRateLimitEnabled(true)
            },
        )
}
```

Three things worth knowing:

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

The `OKTracer` pod lives in the vendor's own spec repository, so `ios/Podfile`
has to declare it as a source. Once you add one custom source you must also
declare the CDN explicitly:

```ruby
source 'https://github.com/odnoklassniki/tracer-ios.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '13.0'
```

`OKTracer` vends a **static** `xcframework`, and CocoaPods refuses to let a
target using dynamic frameworks pull a static binary in transitively. Change the
linkage inside `target 'Runner'`:

```ruby
target 'Runner' do
  use_frameworks! :linkage => :static   # was: use_frameworks!
  ...
end
```

Without this, `pod install` fails with *"The 'Pods-Runner' target has transitive
dependencies that include statically linked binaries"*. It is the same
requirement Firebase's static frameworks impose, and Flutter supports it.

Then `pod install`. The `appToken` **is** passed from Dart on iOS.

### Web and other platforms

Web speaks Tracer's own ingest — the same one the vendor's JS SDK uses — and
wants the JS project's `appToken`, exactly as Android and iOS want theirs. No
Sentry DSN is needed, and none is issued: measured 2026-08-26, a JS project
simply has none. The protocol is written down in
[web-protocol.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/web-protocol.md).

**Desktop and Aurora are not supported in this release.** Neither has a
Flutter-facing Tracer SDK, and no build for either has ever been run against a
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

## Obfuscated release builds

If you build with `--obfuscate --split-debug-info`, Dart stack traces become
addresses:

```
build_id: 'b71885097a7ebc4d1ab80642f606c4be'
#00 abs 0000007938a1c2f0 virt 00000000002cc2f0
```

The package always sends the **verbatim** trace, header included, so it stays
decodable:

```
flutter symbolize -d build/symbols/app.android-arm64.symbols -i trace.txt
```

**Tracer has no documented upload channel for Dart `--split-debug-info` files**,
so decoding is currently a manual step. Read
[symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md)
before you ship an obfuscated build — it explains what does and does not work,
and how to avoid finding out the hard way.

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
