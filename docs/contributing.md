# Working in this monorepo

## CI triggers

Automatic push/PR checks run for source, tests, dependencies and build/workflow
configuration. Changes limited to Markdown, reStructuredText, AsciiDoc, docs
directories, license/notice files, `.gitignore` or `.gitattributes` do not start
CI. Mixed changes that include code still run the relevant checks. Manual
workflow dispatch remains available. Windows runtime checks follow a successful
Windows preparation run, so documentation-only pushes start neither workflow.

## Layout

Seven publishable packages under `packages/`, an unpublished Sentry transport,
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
tool/bootstrap.sh   # pub get everywhere from tool/packages.tsv
tool/check.sh       # format + analyze + test + coverage + publish dry-run
make analyze        # analyze every catalog package, including desktop
make test           # VM/Chrome tests and combined coverage
```

Run the full check from a clean commit. It also fails if analyze, tests, builds or
publish dry-run modify tracked files or leave untracked, non-ignored files. This
is intentional: a dirty-tree publish warning is not ignored.

`tool/packages.tsv` is the single catalog for local commands, CI matrices and
publish dry-run. A failed package does not hide the remaining checks; the final
summary lists passed/failed/skipped work. Desktop unit tests are included, while
native device/live acceptance remains in explicit platform workflows.

Combined unit-test coverage is written to `build/coverage/{index.html,summary.json,lcov.info}`.
The denominator counts production lines reported by the VM. The JSON lists
unmeasured library files and skipped packages (examples and Chrome-only tests).
Generated files are excluded. HTTP runs its VM suite plus its browser lifecycle
and payload tests. Web runs in Chrome. Install Chrome or set `CHROME_EXECUTABLE`
to the browser executable before running `make test` or `make check`. Parser, `TracerClient`, lifecycle and
HTTP transport also have a baseline comparison in `tool/coverage_baseline.json`;
there is no arbitrary global threshold and coverage is not live-delivery proof.
The desktop dry-run explicitly allows only pub's exact-pin warning for
`sentry_flutter 9.30.1`; the constraint is not widened before task 29 acceptance.

## Flutter compatibility

The common packages declare Flutter 3.22.0 as their minimum. CI tests that minimum separately from the
reproducible baseline in `.github/flutter-version`; ordinary PRs never silently
move that pin. The iOS workflow reads the same file. Desktop release acceptance
keeps its separately audited toolchain pin. The desktop package requires Flutter
3.24.0 and its example requires 3.35.0. Both run locally, and the desktop
package participates in the baseline and latest-stable CI jobs.

A latest-stable canary runs on PRs, manual dispatch and a weekly schedule, with
continue-on-error so its signal cannot replace the baseline. It also runs desktop
unit tests. `flutter-baseline-update.yml` opens an unmerged monthly candidate PR
from official stable metadata. Enable “Allow GitHub Actions to create and approve
pull requests” in the repository Actions settings. On the generated PR, select
“Approve workflows to run” to start compatibility checks. Dependabot proposes
GitHub Actions updates.
No update workflow merges a PR or publishes packages.

To reproduce a particular version with FVM:

```sh
fvm install 3.22.0
cd packages/apptracer_flutter
"$HOME/fvm/versions/3.22.0/bin/flutter" test
```

For documentation-only changes, run `python3 tool/check_markdown_links.py` instead
of the full code checks. It validates local files and GitHub-style anchors, and
`.github/workflows/docs.yml` runs the same lightweight check on docs-only PRs.

Per package:

```sh
cd packages/apptracer_flutter
flutter analyze --fatal-infos
flutter test
```

## Changing the native contract

`tool/pigeon/tracer_api.dart` is the
single source of truth for Android/iOS methods and models. Do not edit generated
Dart, Kotlin or Swift files directly. After editing the schema, use Flutter 3.22.0 (the generation job in CI).

```sh
tool/generate_pigeon.sh         # regenerate all three targets
tool/generate_pigeon.sh --check # CI check that outputs are current
```

The generator and its lockfile live under `tool/pigeon`. Only the generated
runtime files ship in the platform packages. Preserve the legacy
`ru.apptracer.flutter/tracer` compatibility layer for independently versioned
packages, and add serialization tests for every new nullable, Unicode or
diagnostic field.

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
   the package catalog in `tool/packages.tsv`, and to `docs/platform-matrix.md` with the coordinates, the
   minimum version, and how you verified them.

## Verifying vendor facts

Documentation drifts; artefacts do not. Where `docs/platform-matrix.md` states a
minimum SDK version, a resource name or an API signature, it also states how it
was checked — from the published AAR, the plugin bytecode, or the
`.swiftinterface` inside the xcframework. Keep that habit when you update it.
