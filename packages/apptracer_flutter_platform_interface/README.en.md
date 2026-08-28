# apptracer_flutter_platform_interface

The common platform interface for [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter), an unofficial
Flutter integration with [Tracer](https://apptracer.ru).

> Not affiliated with, endorsed by, or supported by VK or OK.TECH.

Русская версия: [README.md](README.md).

**Application code should depend on `apptracer_flutter`, not on this package.**
It exists so that platform implementations and the app-facing package can be
versioned independently.

It contains:

* `TracerPlatform` — the contract every implementation extends, plus
  `UnsupportedTracerPlatform`, the inert default that makes a platform without
  an implementation harmless rather than fatal.
* `MethodChannelTracer` — shared by the Android and iOS implementations.
* `DartStackTrace.parse` — a parser for every stack-trace shape a Flutter app
  can produce: JIT frames, obfuscated AOT frames with their `build_id` header,
  `dart2js` frames in V8 and SpiderMonkey notation, and async markers. The
  verbatim text is always preserved, because an obfuscated trace can only be
  decoded by `flutter symbolize` and that needs the original bytes.
* `SyntheticIssueKey` — builds an `issueKey` from the error type and the
  innermost named frame, for backends whose own grouping cannot tell two Dart
  errors apart. Both native implementations use the same one.
* The data models: `TracerOptions`, `TracerEvent`, `TracerBreadcrumb`,
  `TracerSeverity`, `DartStackFrame`.

## Implementing a platform

Extend `TracerPlatform` — never implement it — so that new members can be added
without a breaking change, and register the implementation in `registerWith`.

See the [platform matrix](https://github.com/KonstantenKomkov/apptracer_flutter/blob/main/docs/platform-matrix.md).
