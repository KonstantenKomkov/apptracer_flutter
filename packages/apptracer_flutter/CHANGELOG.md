# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below `1.0.0`, a breaking change bumps the minor version,
as pub.dev expects.

## [Unreleased]

### Removed

- The `meta` dependency, which nothing used. The only annotation in this
  package is `@visibleForTesting`, and it arrives through
  `package:flutter/foundation.dart`, which re-exports it — there is no
  `import 'package:meta/meta.dart'` anywhere here. Resolution is unaffected:
  `meta` stays in the lockfile as a transitive dependency of Flutter itself.
  What goes away is a `^1.12.0` constraint this package had no business
  stating.

## [0.1.1] - 2026-08-30

### Added

- `dart run apptracer_flutter:install_ios_dsym_phase`, which adds the dSYM
  upload build phase to `Runner.xcodeproj`. On CocoaPods the podspec does this
  at `pod install`; an application on Swift Package Manager evaluates no
  podspec, so the step has to be run once by hand. The command finds
  `apptracer_flutter_ios` through the package config and runs the script that
  ships there, so nobody has to dig a path out of the pub cache. Running it
  again refreshes the existing phase instead of adding a second one.

  It needs Ruby with the `xcodeproj` gem — the pair CocoaPods itself runs on —
  and says so when they are missing, along with the file to paste into Xcode
  instead.

### Changed

- Requires `apptracer_flutter_ios` `^0.1.1`, which is where the script the new
  command runs became runnable as a command. Under `^0.1.0` a resolution could
  pick 0.1.0, where that file only defines a method, and the command would
  report success having done nothing.

## [0.1.0] - 2026-08-28

### Added

- `dart run apptracer_flutter:upload_symbols ios|web`, which uploads iOS dSYMs
  and web source maps. Android needs none of it — the Gradle plugin does it
  during the build — and on iOS the vendor's Fastlane plugin does the same on
  archive; web had no tool at all. It reads the version from `pubspec.yaml`,
  takes the token from `--token` or `TRACER_PLUGIN_TOKEN`, and exits non-zero
  unless the server confirms, because an ingest that answers 200 to a body it
  did not understand cannot be trusted on the status code alone. No new
  dependency: the archive is built with `dart:io`'s raw deflate rather than
  `package:archive`, which would otherwise ship in every application.

- Initial release.
- `Tracer.initialize` runs the application inside a guarded zone and calls
  `appRunner` exactly once in every scenario, including disabled collection, a
  platform SDK that fails to start, and a platform with no implementation.
- Captures `FlutterError.onError`, `PlatformDispatcher.instance.onError` and
  guarded-zone errors, chaining to any handler that was already installed and
  restoring it on `stopCollection`.
- Deduplicates an error object that reaches the integration through more than
  one route.
- Breadcrumbs with a bounded buffer, mirrored into the native log buffer so that
  native crashes carry the trail too.
- `beforeSend` and `beforeBreadcrumb` hooks; a hook that throws is logged and
  ignored rather than losing the event.
- Custom keys, user id, and manual error reporting with `severity` and
  `issueKey`.
- `maxRawStackTraceLogBytes` and `maxStackFrames` bound what a pathological
  stack trace can do. Android's log buffer is circular and 64 KiB, so an
  unbounded trace would evict the whole breadcrumb trail; the verbatim text is
  truncated at a line boundary, keeping the `build_id` header and the frames
  nearest the throw.

### Changed

- Android setup no longer asks for a line of manifest. The non-fatal rate limit
  that `ru.apptracer.flutter.TracerApplication` used to carry is applied by
  `apptracer_flutter_android` itself, at process start, so an application
  without an `Application` class of its own gets 10 non-fatals per hour instead
  of the SDK's silent 8 per session with nothing to configure. Applications that
  do have one still override it, and still subclass `TracerApplication` to keep
  the limit.

### Fixed

- The verbatim stack trace now renders in Tracer's log table. The console
  scans the log for the next record marker in sequence — `#3` after `#2` — and
  expects `#0 timestamp | text` where it finds one; a Dart stack trace hands it
  frame numbers that look exactly like that, so the table view showed
  `Match line error` and nothing else. Frame numbers in a readable trace are
  now written `[0]`, `[1]`. An obfuscated AOT trace is untouched byte for byte,
  so `flutter symbolize` still accepts it, and the console never mistook its
  `#00`-style frames for records anyway.

- Grouping on Android. Measured against a live Tracer project on 2026-08-26,
  Tracer keys a group on the top frame's class and method alone: a `StateError`
  and a `TimeoutException` thrown from two closures inside one `build` landed in
  the same group. When the caller supplies no `issueKey`, one is now synthesised
  from the error type and the innermost named frame — the rule iOS already used,
  moved into Dart so both platforms share it. Neither file nor line goes into
  the key, so editing code does not scatter a group.

- The documentation said the package adds no device identifier of its own.
  That was never true of the web path: the implementation mints a UUID, keeps
  it in `localStorage` under `apptracer_flutter.deviceId` and sends it as
  `deviceId` on every event, together with the page host, screen metrics and
  visibility state. The README and `docs/privacy.md` now say what actually
  goes out, and name `deviceId` as the install identifier it is. Whether the
  ingest would take an event without it is left unclaimed — the server answers
  `200` to a malformed body, so its absence cannot be tested.

[Unreleased]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.2...HEAD
[0.1.1]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.1...v0.1.2
[0.1.0]: https://github.com/KonstantenKomkov/apptracer_flutter/releases/tag/v0.1.0
