# Working in this monorepo

## CI triggers

Automatic push/PR checks run for source, tests, dependencies and build/workflow
configuration. Changes limited to Markdown, reStructuredText, AsciiDoc, docs
directories, license/notice files, `.gitignore` or `.gitattributes` skip the Flutter builds and tests.
Markdown changes trigger the documentation workflow. Mixed changes that include
code still run the relevant checks. Manual
workflow dispatch remains available. Windows runtime checks follow a successful
Windows preparation run, so documentation-only pushes start neither workflow.

## Layout

Seven publishable packages under `packages/`, an archived Sentry transport,
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

Every external action in `.github/workflows/` must use a full commit SHA followed by
a version comment, for example `actions/checkout@<40-character-sha> # v7`. Local
`uses: ./...` references are allowed. The lightweight `Action commit pins`
workflow checks changes to workflows, the checker, its dependency and its tests.
A PR changing only `.github/workflows/docs.yml` runs the pins and documentation
checks. Changes under `tool/` also match the existing Flutter CI filter.
Dependabot's root `github-actions` configuration covers the workflow references.

```sh
python3 -m venv build/pins-venv
build/pins-venv/bin/python -m pip install -r tool/requirements-action-pins.txt
build/pins-venv/bin/python -m unittest discover -s tool/tests -p test_action_pins.py
build/pins-venv/bin/python tool/check_action_pins.py
```

For Markdown changes, run the documentation workflow checks with Python 3.10+:

```sh
python3 -m venv build/docs-venv
build/docs-venv/bin/pip install -r docs/tools/requirements.txt
build/docs-venv/bin/python -m unittest discover -s docs/tools
build/docs-venv/bin/python docs/tools/check_markdown_links.py
```

Run the full check from a clean commit. It also fails if analyze, tests, builds or
publish dry-run modify tracked files or leave untracked, non-ignored files. This
is intentional: a dirty-tree publish warning is not ignored.

`tool/packages.tsv` is the single catalog for local commands, CI matrices and
publish dry-run. A failed package does not hide the remaining checks; the final
summary lists passed/failed/skipped work. Desktop unit tests are included, while
native device/live acceptance remains in explicit platform workflows.

Common package coverage is written to `build/coverage/{index.html,summary.json,lcov.info}`.
The denominator counts production lines reported by the VM. The JSON lists
unmeasured library files and skipped packages (examples and Chrome-only tests).
Generated files are excluded. HTTP runs its VM suite plus its browser lifecycle
and payload tests. Web runs in Chrome. Install Chrome or set `CHROME_EXECUTABLE`
to the browser executable before running `make test` or `make check`. Any decrease below the checked-in line coverage for the parser, `TracerClient`,
lifecycle or HTTP transport fails the check after it writes the report. For
an intentional change, review the affected lines and explicitly update the
covered/total counts in `tool/coverage_baseline.json` in the same change.

Desktop coverage is written separately to `build/coverage/desktop-<os>/`.
Each native workflow uploads its host report, including shared adapter code
and files for that OS. The JSON lists the other platforms’ excluded files.
`desktop_lifecycle` compares the line coverage ratio of `sentry_desktop_tracer.dart`
with the current host's entry in `tool/desktop_coverage_baseline.json`. Both
`make check` and `python3 tool/coverage_report.py --desktop-only` fail on a
decrease. Each platform workflow publishes the counts and delta in its job
summary and uploads the report even when the coverage gate fails.

For an intentional change, inspect the affected lines in each host's LCOV
artifact, explain the lifecycle outcomes covered or missed in the PR, and update
the affected host's covered/total pair in the same review. The gates apply to
individual critical files. There is no project-wide 100% coverage target.

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
unit tests. A failed weekly run opens a GitHub issue or adds the run link to
the existing open issue.

The [monthly baseline workflow](../.github/workflows/flutter-baseline-update.yml)
compares the default branch's pin with the official stable release. When an update
is available, it prepares `automation/flutter-baseline-<version>` and puts an
**Открыть PR** link in the run summary. Follow the link and select **Create pull
request** to start the usual compatibility checks. Repeated runs reuse the
candidate for that version. When the pin is current, the summary reports that
and the workflow creates no branch. Dependabot separately proposes GitHub
Actions updates.

To reproduce a particular version with FVM:

```sh
fvm install 3.22.0
cd packages/apptracer_flutter
"$HOME/fvm/versions/3.22.0/bin/flutter" test
```

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
