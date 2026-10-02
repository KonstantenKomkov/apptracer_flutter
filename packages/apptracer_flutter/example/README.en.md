# apptracer_flutter example

Demonstrates every error path `apptracer_flutter` covers, and doubles as the
build target CI uses to prove the Android, iOS and web integrations compile.

Русская версия: [README.md](README.md).

## Run

This directory has a `Makefile` with the per-platform invocations already
spelled out — `make android`, `make ios`, `make web`; `make` on its own lists
them. `.vscode/launch.json` mirrors the same set for anyone launching from the
editor, so opening this folder as its own project is enough. From the
repository root the same targets are `make example-android` and friends. What
follows is what those targets actually run.

Tokens come from the environment; nothing is hard-coded.

Each platform is a separate Tracer project, so each has its own pair of tokens:

```sh
export TRACER_APP_TOKEN=...        # Android, read by the Gradle plugin
export TRACER_PLUGIN_TOKEN=...     # Android, mapping and symbol upload
export TRACER_IOS_APP_TOKEN=...    # iOS
export TRACER_IOS_PLUGIN_TOKEN=... # iOS, dSYM upload
export TRACER_JS_APP_TOKEN=...     # web
export TRACER_JS_PLUGIN_TOKEN=...  # web, source-map upload
```

On Android the token comes from the Gradle plugin, which writes it into a
string resource at build time — `--dart-define` is ignored there:

```sh
env 'ORG_GRADLE_PROJECT_tracer.enabled=true' flutter run --release
```

On iOS and web the token is passed from Dart, a different one each:

```sh
flutter run -d <iphone> --dart-define=TRACER_APP_TOKEN=$TRACER_IOS_APP_TOKEN
flutter run -d chrome   --dart-define=TRACER_APP_TOKEN=$TRACER_JS_APP_TOKEN
```

No Sentry DSN is needed anywhere: web speaks Tracer's own ingest with the same
`appToken`, and the platforms the vendor has no SDK for are not supported by
this example.

Without them the app still runs: the integration reports that it is disabled and
the buttons do nothing but raise errors locally. That is the graceful-degradation
path, and it is worth seeing at least once.

## Android

The Tracer Gradle plugin is opt-in here so that a checkout without credentials
still builds:

```sh
env 'ORG_GRADLE_PROJECT_tracer.enabled=true' flutter build apk --release \
  --obfuscate --split-debug-info=build/symbols
```

`android/app/tracer.gradle` fails the build when `tracer.enabled=true` is
passed without both tokens, rather than producing a release whose crashes go
nowhere. A real application applies the plugin unconditionally; see the
[README](../README.md#android).

After an obfuscated build, check that the symbol file matches the binary:

```sh
../../../tool/verify_build_id.sh
```

An incremental build can leave the Dart AOT step `UP-TO-DATE` and never
regenerate the symbol file — see
[symbolication.md](../../../docs/symbolication.md), finding 3.

## iOS

This example requires iOS 15 or later for the installed Xcode 27 toolchain. The plugin itself retains its iOS 13 deployment requirement.

A device build needs your Team ID. The project deliberately does not carry one:
it belongs to a person, not to the example. Copy the template and fill it in:

```sh
cp ios/Flutter/Signing.xcconfig.example ios/Flutter/Signing.xcconfig
```

The Team ID is in `security find-identity -v -p codesigning`, in parentheses
after the name. The file is gitignored. Without it a simulator build works as
usual and a device build fails with Xcode's own message about the missing team.

You also need an Apple ID added in Xcode: **Settings → Accounts**. A certificate
in the keychain is not enough — without the account Xcode will not issue a
profile and says `No Account for Team`.

`ios/Podfile` declares the vendor's spec repository and uses
`use_frameworks! :linkage => :static`, which `OKTracer`'s static xcframework
requires.

```sh
flutter build ios --simulator --debug
```

## Web

```sh
flutter build web --release --source-maps
TRACER_PLUGIN_TOKEN=... ../../../tool/upload_web_sourcemaps.sh 1.0.0
```

## Driving the checks automatically

```sh
make live-check
```

Runs `integration_test/live_verification_test.dart` on a connected Android
device: it presses the buttons in the order the checks in
[live-verification-plan.md](../../../docs/live-verification-plan.md) require,
asserts everything observable from Dart, and prints what is left to confirm by
eye in the Tracer console. What it deliberately does not cover, and why, is
documented at the top of the test.

## What the buttons do

| Button | Path exercised |
|---|---|
| Бросить синхронно | uncaught synchronous error in a callback |
| Бросить асинхронно | `Timer.run` throw, caught by the guarded zone |
| Бросить из future без await | async error with no `await` |
| Бросить внутри build() виджета | `FlutterError.onError` |
| Отправить пойманную ошибку | manual `Tracer.recordError` with `issueKey` and custom keys |
| Добавить breadcrumb | `Tracer.log` |
| Задать кастомный ключ | `Tracer.setCustomKey` |
| Остановить сбор | `Tracer.stopCollection`, including handler restoration |
| Уронить процесс нативно | SIGSEGV to our own process — the native SDK's path, not Dart's |
| Заблокировать главный поток (ANR) | 10 seconds on the Android main thread — the ANR watchdog's path |

The last two are Android-only and end the session: the app has to be started
again afterwards. They are backed by the example's `MainActivity`, not by
package code.


## Deferred collection verification

`lib/consent_main.dart` exposes explicit start, state query, revoke with cleanup,
and Dart/JVM/native/ANR probes. The `consent` flavor uses a separate `.consent`
application ID and removes both startup providers. Ordinary example builds retain
automatic mode.

Load the local Android Tracer project tokens from the repository root:

```sh
source .env.tracer
cd packages/apptracer_flutter/example
env 'ORG_GRADLE_PROJECT_tracer.deferred=true' \
    'ORG_GRADLE_PROJECT_tracer.enabled=true' \
    flutter run --flavor consent --target lib/consent_main.dart \
    --dart-define=TRACER_TEST_USER=consent-test-A
```

Omit `tracer.enabled` for the SDK-absent variant: it needs no tokens and returns
`unsupported/sdk_missing`. Git ignores `.env.tracer`. See the
[verification plan](../../../docs/native-collection-consent.md#device-verification-harness--2026-10-02)
for scenarios and evidence limits. Collection, revocation and delivery verification
is complete for Android, iOS and Web. The evidence ledger records remaining
symbolication limits for Android native and optimized Web frames.
