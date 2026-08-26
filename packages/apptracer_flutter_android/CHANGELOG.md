# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below `1.0.0`, a breaking change bumps the minor version,
as pub.dev expects.

## [Unreleased]

## [0.1.0] - 2026-08-25

### Added

- Initial release.
- Forwards Dart errors to `ru.ok.tracer:tracer-crash-report` as a synthetic
  `Throwable` whose stack frames are the Dart frames, so Tracer groups by the
  Dart call site rather than by the identical JNI frames.
- Maps breadcrumbs onto `TracerCrashReport.log` and custom keys onto
  `Tracer.setCustomProperty`.
- Detects a missing Tracer SDK or a missing `ru.ok.tracer` Gradle plugin and
  reports "disabled" with an actionable message instead of crashing.
- The Tracer SDK is a `compileOnly` dependency: this package never pins a vendor
  SDK version into a host build and redistributes nothing.

[Unreleased]: https://github.com/komkovkonstantin/apptracer_flutter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/komkovkonstantin/apptracer_flutter/releases/tag/v0.1.0
