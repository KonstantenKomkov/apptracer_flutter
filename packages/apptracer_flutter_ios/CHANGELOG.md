# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below `1.0.0`, a breaking change bumps the minor version,
as pub.dev expects.

## [Unreleased]

## [0.1.1] - 2026-08-30

### Added

- Swift Package Manager support. Flutter warns on every iOS build that a plugin
  carrying only a podspec "does not support Swift Package Manager" and that this
  "will become an error in a future version of Flutter", so the package now
  ships a `Package.swift` beside the podspec and both build the same sources
  from the layout Swift Package Manager expects. `OKTracer` is declared there
  the way the podspec declares it — by version, from the vendor's own
  repository, which publishes the SDK as binary targets — so nothing is
  redistributed and no SDK version is pinned into a host build.

  The manifest declares no dependency on `FlutterFramework`, the package Flutter
  generates for its own framework: `import Flutter` resolves through the
  framework search paths Flutter passes to the build. That keeps the `flutter:`
  constraint honest at `>=3.22.0` for both paths — a manifest depending on
  `../FlutterFramework` would need Flutter 3.41, where that package first
  appears, and would fail to resolve for anyone who turned Swift Package Manager
  on before then. `url_launcher_ios` from `flutter/packages` and
  `vkid_flutter_sdk` ship the same shape.

  The product is static, because `OKTracer` is a static xcframework — the same
  requirement the podspec's `use_frameworks! :linkage => :static` puts on a
  CocoaPods application.

  Verified on Flutter 3.44.9 in an application with no CocoaPods integration at
  all: the build links the plugin (`AppTracerFlutterPlugin`, `DartLogProvider`
  and `GeneratedPluginRegistrant` are in `Runner.debug.dylib`) together with the
  vendor's `TracerResources.framework`, and Flutter reports "All plugins found
  for ios are Swift Packages" instead of the warning. The CocoaPods path was
  rebuilt unchanged.

### Changed

- The build phase that uploads `dSYM`s is now a file of its own,
  `ios/tracer_dsym_upload_phase.sh`, and the code that installs it is a
  standalone script, `ios/tracer_add_upload_phase.rb`, in the shape
  firebase_crashlytics uses. The podspec still runs it at `pod install`; on
  Swift Package Manager, where no podspec is evaluated, the same script is what
  `dart run apptracer_flutter:install_ios_dsym_phase` calls, and the phase's
  text is a file a reader can paste into Xcode rather than a heredoc inside
  Ruby.

## [0.1.0] - 2026-08-28

### Added

- `pod install` adds a build phase to the application's `Runner.xcodeproj` that
  uploads `dSYM`s on every release build, which is how `firebase_crashlytics`
  arranges the same thing. A phase declared in this pod's own podspec would not
  do: it belongs to the pod target and runs before the application is linked,
  when `Runner.app.dSYM` does not exist yet. The phase reads the token from
  `TRACER_IOS_PLUGIN_TOKEN`, `TRACER_PLUGIN_TOKEN` or `ios/tracer_plugin_token`,
  warns instead of failing the build when it cannot upload, and is skipped
  entirely with `TRACER_SKIP_IOS_PHASE=1`.

- Initial release.
- Forwards Dart errors to `OKTracer` as `TracerNonFatalModel`, carrying the Dart
  frames as `callStackSymbols`.
- Synthesises an `issueKey` from the Dart error type and the innermost named
  frame, because a Dart trace has no native addresses to group on and Tracer
  ignores supplied symbols outside a debugger. The key deliberately excludes the
  file and line: Tracer omits both from its own grouping so that a code edit
  cannot split an issue, and an `issueKey` is used verbatim, so including them
  would have reintroduced that instability.
- Delivers breadcrumbs through `TracerLogProviderProtocol`, which leaves the
  SDK's own logging verbosity untouched.

- `TracerOptions.debug` now wires the SDK's own console log and a
  `TracerServiceDelegate`, so a rejected or failed upload says so instead of
  vanishing. Note that the SDK's log includes the upload URL with its token.

### Changed

- A non-fatal now carries a single placeholder native address rather than the
  real `Thread.callStackReturnAddresses`. Both satisfy the SDK's requirement
  that the array not be empty, but the real stack filled every report with
  twenty frames of UIKit, CoreFoundation and libdispatch — none of them related
  to the error — and each rendered `Missing Binary image` in the console,
  including in the event title. Uploading the app's dSYM does not resolve those:
  measured twice on 2026-08-26, symbols are accepted but not applied to
  non-fatal reports. The Dart stack trace travels in the attached log, which is
  the copy that is readable anyway.

  If you ran pre-release builds of this package against a live project, their
  issues do not carry over: Tracer builds an issue title from its rendering of
  the top frame, so the same `issueKey` under a different top frame lands in a
  new group. Those events sit under
  `Missing Binary image with UUID = … - <message>`, these under
  `+ 0 - <message>`.

### Fixed

- A non-fatal must carry a non-empty `callStackAddresses`, or the SDK drops it
  before any network call — its delegate answers `callStackAddresses is empty`
  from `CrashReporterService.getThreadInfo`, and nothing whatsoever reaches the
  project. A Dart stack trace has no native addresses, so the native stack of
  the reporting call is passed instead; it is the same for every Dart error,
  which is why grouping relies on the `issueKey` synthesised on the Dart
  side.

- The README's `Podfile` snippet omitted `use_frameworks! :linkage => :static`,
  so following it verbatim failed `pod install`: `OKTracer` ships as a static
  `xcframework`. The snippet is complete now, and the README also says that
  `pod install` writes a `dSYM` upload phase into `Runner.xcodeproj` and that
  `TRACER_SKIP_IOS_PHASE=1` keeps it away from the project file.

[Unreleased]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.2...HEAD
[0.1.1]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.1...v0.1.2
[0.1.0]: https://github.com/KonstantenKomkov/apptracer_flutter/releases/tag/v0.1.0
