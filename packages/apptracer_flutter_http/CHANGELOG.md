# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below `1.0.0`, a breaking change bumps the minor version,
as pub.dev expects.

## [Unreleased]

- Preserve anonymous release web frame coordinates in JS_STACKTRACE payloads.

- Support explicit start and stop-with-cleanup for HTTP/Web. Discard logs, keys,
  user ID and token at stop; reject diagnostics while off. Recreate an owned HTTP
  client at the next start so re-consent can send events again.

### Changed

- Normalize symbolic Dart debug/VM frames to JavaScript V8 syntax for the Tracer stack parser, retaining the original event trace.

- Prepare `0.2.0-dev.1` for local lifecycle verification; this is not an accepted
  or published release.
- Update the platform-interface constraint for the lifecycle contract and remove the direct meta dependency. Native deferred lifecycle operations remain unsupported.

## [0.1.0] - 2026-08-28

### Added

- The transport reads `resolvedEnvironment`, and takes `versionCode` from
  `dist` when it is set, so a real build number is reported rather than one
  derived from the version name — `1.2.3` and `1.2.3+7` were otherwise the
  same build.

- The transport reads `TracerOptions.resolvedAppToken`, so `webAppToken` is
  honoured where it is set.

- Initial release.
- `TracerHttpTracer`, a pure-Dart `TracerPlatform` that posts to Tracer's own
  ingest — `POST /api/crash/uploadBatch`, authenticated by the project's
  `appToken`. Used by web, and registered by hand on desktop and Aurora OS.
- `TracerClientFacts` with a browser implementation in `apptracer_flutter_web`
  and `PlatformClientFacts` elsewhere.
- A network failure never propagates into the host application.

- Breadcrumbs, custom keys and `userId`. Breadcrumbs travel in `logsFile` as
  base64 of `#<index> <epoch millis> | <text>` rows, capped at 64 000 bytes
  with the oldest dropped first — the format `LogsData` in `@apptracer/sdk`
  2.6.9 uses, and the one the console's log table insists on.
- `TracerLogBuffer`, holding that log, with the row format pinned by tests.

### Changed

- Custom keys are sent both as `uploadBean.properties` and as
  `uploadBean.tags`. The vendor's SDK sends only tags, but the console's data
  tab reads only properties; measured 2026-08-27 by sending one event each way.

### Note on the name

Released as `apptracer_flutter_http`. It was written as
`apptracer_flutter_sentry` and spoke the Sentry protocol, on the belief that
Tracer ingests that way on platforms without a native SDK. Measured against a
live project on 2026-08-26, no project is issued a DSN and the vendor's own SDKs
post to their own API, so both the name and the protocol were replaced before
the first release.

[Unreleased]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/KonstantenKomkov/apptracer_flutter/releases/tag/v0.1.0
