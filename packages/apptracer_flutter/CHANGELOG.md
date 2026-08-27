# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below `1.0.0`, a breaking change bumps the minor version,
as pub.dev expects.

## [Unreleased]

## [0.1.0] - 2026-08-27

### Added

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

[Unreleased]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/KonstantenKomkov/apptracer_flutter/releases/tag/v0.1.0

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
