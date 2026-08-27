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

[Unreleased]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/KonstantenKomkov/apptracer_flutter/releases/tag/v0.1.0

- `TracerOptions.debug` now wires the SDK's own console log and a
  `TracerServiceDelegate`, so a rejected or failed upload says so instead of
  vanishing. Note that the SDK's log includes the upload URL with its token.

### Fixed

- A non-fatal must carry a non-empty `callStackAddresses`, or the SDK drops it
  before any network call — its delegate answers `callStackAddresses is empty`
  from `CrashReporterService.getThreadInfo`, and nothing whatsoever reaches the
  project. A Dart stack trace has no native addresses, so the native stack of
  the reporting call is passed instead; it is the same for every Dart error,
  which is why grouping relies on the `issueKey` synthesised on the Dart
  side.

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
