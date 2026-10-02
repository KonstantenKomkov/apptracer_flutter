# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below `1.0.0`, a breaking change bumps the minor version,
as pub.dev expects.

## [Unreleased]

## [0.2.0] - 2026-10-03

### Changed

- Use synthetic grouping keys for Dart errors and report SDK version `0.2.0`.
- Require HTTP transport and platform interface `^0.2.0`, including diagnostic
  cleanup on stop, client recreation on re-consent, and anonymous frame coordinates
  for release source maps. Native deferred lifecycle operations remain unsupported.


## [0.1.0] - 2026-08-28

### Added

- The version is read from the `version.json` that `flutter build web` writes,
  which carries `version:` from `pubspec.yaml`. This is web's equivalent of the
  bundle version Android and iOS read for themselves, and it is why `release`
  no longer has to be passed. A missing or unreadable file changes nothing:
  whatever the options said still stands.

- Initial release.
- Registers the pure-Dart transport as the web implementation. Tracer's
  JavaScript SDK ships only as an npm package, which a Flutter web build cannot
  bundle, so this speaks the same ingest that SDK speaks —
  `POST /api/crash/uploadBatch`, authenticated by the project's `appToken` —
  from Dart.

### Fixed

- Documented the `deviceId` this package creates: a UUID in `localStorage`
  under `apptracer_flutter.deviceId`, sent with every event and surviving until
  the viewer clears site data. In a private window, or with site data blocked,
  it lives as long as the tab. Nothing about the behaviour changed; the README
  simply did not mention it.

[Unreleased]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/KonstantenKomkov/apptracer_flutter/compare/v0.1.3...v0.2.0
[0.1.0]: https://github.com/KonstantenKomkov/apptracer_flutter/releases/tag/v0.1.0
