# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below `1.0.0`, a breaking change bumps the minor version,
as pub.dev expects.

## [Unreleased]

### Fixed

- Grouping on Android. Measured against a live Tracer project on 2026-08-26,
  Tracer keys a group on the top frame's class and method alone: a `StateError`
  and a `TimeoutException` thrown from two closures inside one `build` landed in
  the same group. When the caller supplies no `issueKey`, one is now synthesised
  from the error type and the innermost named frame — the rule iOS already used,
  moved into Dart so both platforms share it. Neither file nor line goes into
  the key, so editing code does not scatter a group.

## [0.1.0] - 2026-08-25

### Added

- Initial release.
- `TracerPlatform` contract and the inert `UnsupportedTracerPlatform` default.
- `MethodChannelTracer`, shared by the Android and iOS implementations, which
  degrades to "disabled" on `MissingPluginException` or `PlatformException`
  instead of propagating.
- `DartStackTrace.parse`, covering JIT frames, obfuscated AOT frames together
  with the `build_id` header, `dart2js` frames in V8 and SpiderMonkey notation,
  and the `<asynchronous suspension>` marker. Unrecognised lines are preserved
  rather than dropped, and the verbatim text is always kept.
- `TracerOptions`, `TracerEvent`, `TracerBreadcrumb`, `TracerSeverity`.
- `DartStackTrace.limitFrames`, which caps the parsed frames while leaving the
  verbatim text whole — trimming that would destroy the only artefact an
  obfuscated trace can be decoded from.

[Unreleased]: https://github.com/komkovkonstantin/apptracer_flutter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/komkovkonstantin/apptracer_flutter/releases/tag/v0.1.0
