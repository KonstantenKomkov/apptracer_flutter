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
three pairs. Both values live under **Settings → Project → API**.

They are needed at different times. The `appToken` belongs to the application,
which sends events with it and does nothing without it. The `pluginToken`
belongs to the build, which uploads symbols with it — and until the first
release it is not needed at all.

**2. Wire the Tracer SDK into your build.** The package does not pull the SDKs
in — your application adds them.

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

On Android the token comes from here only: there is no runtime alternative,
which is why the Gradle plugin is required.

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

That is all Android needs: the one setting without which the package loses
errors silently, it applies to itself. That setting is the softer non-fatal rate
limit. Tracer's hard default is **8 non-fatals per session**
(`LIMIT_MAX_NON_FATALS_PER_SESSION`), and every Dart error the package reports
is a non-fatal — so that is the ceiling your app meets first, and it meets it
silently. The rate limit raises it to 10 per hour, and the vendor recommends
turning it on.

Four more things that are easy to trip over:

* **`TracerOptions.appToken` is ignored on Android.** The token comes from the
  Gradle plugin. The plugin logs a warning if you pass one anyway rather than
  pretending it took effect.
* By default the SDK does not upload from debug builds. The only way to turn
  that on is an `Application` of your own implementing
  `HasTracerConfiguration` (`setDebugUpload`) — and such an `Application`
  replaces the package's settings whole. To keep the rate limit, subclass
  `ru.apptracer.flutter.TracerApplication` and add yours to
  `super.tracerConfiguration`.
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

Then `pod install`. The `appToken` is passed from Dart, one step below.

The iOS project's `pluginToken` plays no part here: it is needed when uploading
the `dSYM`, without which native crashes stay unreadable in the console.

They upload themselves. At `pod install` the package adds a build phase to
`Runner.xcodeproj`, and it ships the `dSYM` on every **release** build — the same
thing Firebase Crashlytics does. Nothing to call; all it needs is the token, and
it looks for it in two places.

First, a file at `ios/tracer_plugin_token`, next to the `Podfile`. Create it and
put one line inside: the iOS project's `pluginToken` from the Tracer console.
The whole file is this:

```
e4f1b0c2-8a7d-4c19-9f3e-2b6d5a0c7e18
```

It holds a secret, so add it to `.gitignore`.

Second, an environment variable, which is what CI usually supplies: the phase
reads `TRACER_IOS_PLUGIN_TOKEN`, or `TRACER_PLUGIN_TOKEN` if that is unset. Then
no file is needed.

With no token the phase warns and skips; when an upload fails it warns and
carries on, because failing an archive over a network hiccup is worse than
producing one without symbols.

To turn it off, delete the phase in Xcode — it is labelled `[apptracer_flutter]`
— or set `TRACER_SKIP_IOS_PHASE=1`, and `pod install` will leave the project
file alone.

If releases are built in CI and you want the pipeline to **fail** when symbols
do not make it, call the upload explicitly; this command exits non-zero:

```sh
flutter build ipa
dart run apptracer_flutter:upload_symbols ios --token=IOS_PLUGIN_TOKEN
```

Finally, the same request by hand, if you would rather install nothing:

```sh
archive=build/ios/archive/Runner.xcarchive
plist=$archive/Products/Applications/Runner.app/Info.plist

cd $archive/dSYMs && zip -qry /tmp/dsym.zip ./*.dSYM

curl --location --http1.1 \
  --form versionName="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" \
  --form versionCode="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" \
  --form file=@/tmp/dsym.zip \
  "https://plugin-api.apptracer.ru/api/symbol/upload?symbolToken=IOS_PLUGIN_TOKEN"
```

`{"success":true}` means accepted.

**By hand, this happens for every release and before the first crashes
arrive.** Each build has its own `dSYM`s with their own UUIDs, so last version's
symbols do not fit this one, and the version is read out of the built
`Info.plist` rather than typed: let it drift from what the application reports
and the symbols land against a different version, silently. Tracer has no
re-symbolication — symbols apply only to events received after the upload.

### Web

Nothing to add: the pure-Dart implementation is already inside the package. The
token is the JS project's `appToken`, passed one step below.

The JS project's `pluginToken`, as on iOS, is not for events but for uploading
source maps — without them a release build's stack traces stay minified. The
vendor has no tool for this, so the package's command is the route:

```sh
flutter build web --release --source-maps
dart run apptracer_flutter:upload_symbols web --token=WEB_PLUGIN_TOKEN
```

It takes only the `.js` and `.map` files out of `build/web`, packs them so their
paths match the paths in the frames, and uses the version from `pubspec.yaml` —
which has to match the `release` in `TracerOptions`.

The same request by hand:

```sh
flutter build web --release --source-maps
cd build/web && zip -qr /tmp/sourcemaps.zip . -i '*.js' '*.map'

curl --location \
  -F sourcemapToken=WEB_PLUGIN_TOKEN \
  -F versionName=1.0.0 \
  -F file=@/tmp/sourcemaps.zip \
  https://plugin-api.apptracer.ru/api/sourcemap/upload
```

As on iOS: every release, and before the deploy — source maps apply only to what
arrives after they are uploaded.

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

There is no Android field: its SDK reads the token from a resource the Gradle
plugin generates, and nothing from Dart overrides it. For a single platform the
shared `appToken` is enough — it is used wherever no specific one is set.

`appRunner` is your application's startup, handed to the package as a function:
usually `() => runApp(const MyApp())`. The package calls it itself, from inside
the guarded zone. That is the only way asynchronous errors nobody awaited reach
that zone, and the only way `WidgetsFlutterBinding.ensureInitialized()` ends up
in the same zone as `runApp` — otherwise Flutter complains that the zones differ.

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

It is almost always one of five things:

* **The platform setup was skipped.** At startup the package prints a line
  saying it is disabled and why, and `Tracer.isEnabled` is `false` at that
  moment. Read the log first.
* **It is a debug build.** The native SDK sends nothing from debug builds by
  default, on either platform. Test on release, or turn on `setDebugUpload`
  (Android, above).
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

## Comparison with Firebase Crashlytics

A fair question: Firebase Crashlytics is free, official, and does the same job.

| | apptracer_flutter | firebase_crashlytics |
|---|---|---|
| Whose SDKs, and where reports go | native SDKs by VK / OK.TECH, ingest in their infrastructure | Google's SDKs, ingest in Google's infrastructure |
| Platforms | Android, iOS, web | Android, iOS, macOS |
| Dart error capture | `FlutterError.onError`, `PlatformDispatcher.onError`, a guarded zone | `FlutterError.onError`, `PlatformDispatcher.onError` |
| Obfuscated Dart | by hand: `flutter symbolize` against the archived symbol file | Android — `firebase crashlytics:symbols:upload`; iOS — automatic |
| Native symbols, every build | Android — the Gradle plugin itself; iOS — a build phase the package writes for you; web — the package's command | Android — through the Firebase CLI; iOS — through an Xcode build phase |

**About the data.** This is the main reason to pick Tracer: Firebase
Crashlytics means Google's SDKs and Google's ingest, Tracer means VK /
OK.TECH's, with an ingest in Russian networks, so no report crosses the border
— which does not make a crash log anonymous, since what makes it personal data
is what you put in it, and exactly what leaves the device is listed in
[privacy.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md).

## What you get beyond Dart errors

Dart errors are this package's job and arrive the same from every platform.
What differs is everything else, because the vendor's native SDK does that
part:

* **Android** — native crashes and ANRs. ANRs only from Android 11: `AnrReporter`
  in `tracer-crash-report` 1.4.0 builds its report from `ApplicationExitInfo`,
  which arrived in API 30, and below that `setSendAnr(true)` buys nothing.
* **iOS** — native crashes and the hang counter.
* **Web** — Dart errors only; there is no such thing as a native crash there.

On a platform with no implementation the package is inert: `isEnabled` is
`false`, one diagnostic line is printed, nothing throws, and your app still
starts. Full details in [platform-matrix.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md).

## Usage

`appRunner` — the startup function from step 3 — runs **exactly once, in every
scenario** — a normal start, a start with collection disabled by policy, a
platform SDK that throws while starting, and a platform with no implementation
at all. An error reporter that can stop an application from starting is worse
than no error reporter.

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

Neither of these is analytics: nothing here is sent on its own. Breadcrumbs are
the trail of what happened before a failure, keys are a snapshot of the state at
the moment of it, and both travel attached to an error report — with no error
they are simply evicted from the buffer. A key lives until the end of the
session, which is why you remove it: otherwise `checkout_step=3` arrives with a
crash in the settings screen and misleads whoever reads it, and stale keys crowd
out useful ones — Tracer keeps at most 30.

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

The verbatim trace — the raw text Dart printed, the one `flutter symbolize`
knows how to decode — is written to the platform log and capped at 8 KiB by
default, and the parsed frames at 128.

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

On Android and iOS this package adds **no personal data of its own**: no
install id, no device id, no user id, no automatic context. Everything it sends
is a property of the error or something you handed it explicitly.

Web is different. The wire format is copied from the vendor's JS SDK, which
always sends a `deviceId`, so the implementation creates one — a UUID in
`localStorage`, the same one until site data is cleared — and sends `host`,
screen size, orientation angle and `visibilityState` alongside it. There is no
way to turn that off.

The native SDKs are a separate matter — the Android SDK collects device model,
manufacturer, ABI, OS version, mobile operator and installer package on its own,
whether or not this package is installed. The full table, and how to constrain
it, is in [privacy.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/privacy.md).

### Grouping

When the caller supplies no `issueKey`, the package synthesises one from the
error type and the innermost named frame, bounded to 32 characters.

This is not decoration. On Android, Tracer keys a group on the top frame's class
and method and nothing else.

Neither the file nor the line number goes into the key: Tracer ignores them by
design, so that editing code does not scatter one issue across several groups,
and the synthetic key preserves that. An `issueKey` you pass to `recordError`
always wins.

## Release builds with `--split-debug-info`

If you build with `--split-debug-info` — with or without `--obfuscate` — Dart
stack traces become addresses:

```
build_id: 'b71885097a7ebc4d1ab80642f606c4be'
#00 abs 0000007938a1c2f0 virt 00000000002cc2f0
```

The package sends the **verbatim** trace by default, header included, so it
stays decodable.

The text sits in the event's log tab, under the line
`--- apptracer_flutter: verbatim Dart stack trace ---`. Copy the trace itself
out of it — from the `build_id:` line down to the last `#NN abs …` frame — and
save it to a file; the service lines the package wrote above it are not part of
the trace. Then:

```
flutter symbolize -d build/symbols/app.android-arm64.symbols -i trace.txt
```

The symbol file has to come from **that same build**: the `build_id` in the
trace must match the `app.<platform>-<arch>.symbols` that `--split-debug-info`
wrote next to the artefact. A neighbouring release's symbols will not do, so
archive them for every build. If the trace ends in
`... [apptracer_flutter] truncated, N more line(s)`, the log cut the tail off:
only the surviving frames decode, and the cap is
`TracerOptions.maxRawStackTraceLogBytes`.

**Tracer has no upload channel for Dart `--split-debug-info` files** — the
vendor confirmed as much — so decoding stays a manual step. Details in
[symbolication.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/symbolication.md).

## License

MIT. The vendor SDKs are licensed separately; see
[legal.md](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/legal.md).
