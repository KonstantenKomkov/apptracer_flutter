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
- `TracerHttpTracer`, a pure-Dart `TracerPlatform` that posts to Tracer's own
  ingest — `POST /api/crash/uploadBatch`, authenticated by the project's
  `appToken`. Used by web, and registered by hand on desktop and Aurora OS.
- `TracerClientFacts` with a browser implementation in `apptracer_flutter_web`
  and `PlatformClientFacts` elsewhere.
- A network failure never propagates into the host application.

### Note on the name

Released as `apptracer_flutter_http`. It was written as
`apptracer_flutter_sentry` and spoke the Sentry protocol, on the belief that
Tracer ingests that way on platforms without a native SDK. Measured against a
live project on 2026-08-26, no project is issued a DSN and the vendor's own SDKs
post to their own API, so both the name and the protocol were replaced before
the first release.

[Unreleased]: https://github.com/komkovkonstantin/apptracer_flutter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/komkovkonstantin/apptracer_flutter/releases/tag/v0.1.0
