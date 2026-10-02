# Working in this monorepo

## Layout

Six publishable packages under `packages/`, an unpublished Sentry transport,
and an example application at `packages/apptracer_flutter/example`.

The packages depend on each other by **version**, exactly as a consumer would,
and are wired together locally through `pubspec_overrides.yaml`. Pub omits that
file from the package archive, but local checks and CI still use its overrides.
They can therefore hide invalid hosted version constraints. Publication checks
must also resolve without overrides, after the required sibling versions are
available on pub.dev; see [publishing.md](publishing.md).

`pubspec_overrides.yaml` has to cover the whole transitive path, not just direct
dependencies, while new sibling versions are not yet available on pub.dev.

## Commands

```sh
tool/bootstrap.sh   # pub get everywhere
tool/check.sh       # format + analyze + test + publish dry-run, same order as CI
```

Per package:

```sh
cd packages/apptracer_flutter
flutter analyze --fatal-infos
flutter test
```

## Where the risky code lives

Four places account for most of what can go subtly wrong. Change them with
tests.

* **`DartStackTrace.parse`** — five different trace formats, and one of them
  (obfuscated AOT) is unreadable if a single header line is misclassified as a
  frame. The verbatim text must survive untouched; anything that reformats it
  destroys the only artefact `flutter symbolize` can consume.
* **`ErrorHandlerChain`** — chains to the handler that was already installed and
  restores it only when the currently installed handler is still ours. Getting
  restore wrong either deletes a third party's handler or resurrects a stale
  one.
* **`Tracer.initialize`** — `appRunner` must run exactly once on every path,
  including the failure paths. There is a test for each path; add one when you
  add a path.
* **`DartError.toStackTrace`** (Kotlin) — the mapping from Dart frames onto
  `StackTraceElement` is what Tracer groups by on Android. Report the JVM stack
  instead and every Dart error in the application collapses into one issue.

## Adding a platform

1. Create `packages/apptracer_flutter_<platform>`.
2. Extend `TracerPlatform` — never implement it; the `PlatformInterface` token
   check is what lets the interface grow without breaking implementations.
3. Declare `implements: apptracer_flutter` and a `dartPluginClass` with a
   `registerWith`.
4. Add it to `default_package` in `packages/apptracer_flutter/pubspec.yaml`, to
   the CI matrix, and to `docs/platform-matrix.md` with the coordinates, the
   minimum version, and how you verified them.

## Verifying vendor facts

Documentation drifts; artefacts do not. Where `docs/platform-matrix.md` states a
minimum SDK version, a resource name or an API signature, it also states how it
was checked — from the published AAR, the plugin bytecode, or the
`.swiftinterface` inside the xcframework. Keep that habit when you update it.
