# Desktop installation and migration

The optional `apptracer_flutter_desktop` package is experimental and unpublished.
The accepted macOS scope is recorded in
[macos-lifecycle-acceptance.md](macos-lifecycle-acceptance.md).
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

The adapter registers automatically on macOS/Windows. Call the normal
`Tracer.initialize` API with the target project's DSN; do not call
`SentryFlutter.init` in addition. For deferred consent, set
`nativeInitialization: TracerNativeInitialization.deferred` and explicitly
start collection after authorization. Inspect the returned collection state.
Use separate projects/configuration for each target. Plugin upload tokens belong
only in the symbol-upload environment, never in Dart defines or the app bundle.

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
