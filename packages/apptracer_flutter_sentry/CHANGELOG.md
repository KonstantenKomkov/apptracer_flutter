# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below `1.0.0`, a breaking change bumps the minor version,
as pub.dev expects.

## [Unreleased]

### Changed

- Not published to pub.dev for now (`publish_to: none`). The platforms this
  transport exists for — desktop and Aurora OS — are outside the 0.1.0 release
  and have never been run against a live Tracer project, so publishing it would
  offer a package nobody has watched deliver an error. Depend on it from git
  until that changes.

## [0.1.0] - 2026-08-27

### Added

- `SentryProtocolTracer`, a pure-Dart `TracerPlatform` that posts Sentry
  envelopes to a Tracer DSN. Tracer documents this route for platforms where it
  has no SDK of its own, and issues the DSN for a project created through VK
  Cloud — for Flutter that means desktop, and Aurora OS when the vendor's C/C++
  SDK cannot be reached from Dart.
- Byte-accurate envelope framing, frames ordered oldest-first as Sentry expects,
  `in_app` classification, breadcrumbs, tags, `fingerprint` from an explicit
  `issueKey`, and the verbatim Dart stack trace under `extra`.
- Honours HTTP 429 with a `Retry-After` back-off; a network failure never
  propagates into the host application.
- A malformed DSN disables collection loudly at startup rather than swallowing
  every event afterwards.

### Note on web

Web does **not** use this package. Tracer has its own JavaScript SDK there, an
ordinary JS project is issued no DSN, and `apptracer_flutter_web` speaks the
same HTTP ingest that SDK speaks. See `docs/web-protocol.md`.
