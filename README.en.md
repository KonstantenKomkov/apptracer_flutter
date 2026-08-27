# apptracer_flutter — the repository

> **This is the monorepo's README: building, documentation, internals.** If
> you only want to add the package to an application, you want
> [packages/apptracer_flutter/README.en.md](packages/apptracer_flutter/README.en.md)
> instead — the same file pub.dev renders, and it opens with a quick start.

Unofficial Flutter integration with [Tracer](https://apptracer.ru), the
error-monitoring service by OK.TECH / VK.

> **Not an official SDK.** Not affiliated with, endorsed by, or supported by VK
> or OK.TECH. This is an independent wrapper around the vendor's public SDKs; it
> does not redistribute them. Report problems here, not to Tracer support.

The native Tracer SDKs cannot see Dart errors — an unhandled Dart exception does
not terminate the process and never enters the JVM, so the `UncaughtException`
handler, the signal handler and the ANR watchdog all miss it. For a Flutter
application that is most of the errors. This repository closes that gap.

Русская версия: [README.md](README.md).

## Repository layout

```
packages/
  apptracer_flutter/                    what applications depend on
  apptracer_flutter_platform_interface/ models, stack-trace parser, contract
  apptracer_flutter_android/            Kotlin bridge to ru.ok.tracer
  apptracer_flutter_ios/                Swift bridge to OKTracer
  apptracer_flutter_web/                web implementation
  apptracer_flutter_http/             pure-Dart Sentry-protocol transport
docs/
tool/
  bootstrap.sh              pub get in every package
  check.sh                  format + analyze + test + publish dry-run
  verify_build_id.sh        fail a release whose Dart symbols do not match it
  prepare_dart_symbols.sh   stage Dart AOT symbols for the Tracer uploader
                            (accepted, but never applied — symbolication.md)
  upload_web_sourcemaps.sh  fail-closed source-map upload
  elf_build_id.py           dependency-free GNU build-id reader
```

## Documentation

| Document | What it answers |
|---|---|
| [live-verification-plan.md](docs/live-verification-plan.md) | step-by-step checklist for proving the integration against a real Tracer project — start here before publishing |
| [platform-matrix.md](docs/platform-matrix.md) | which SDK, which version, which minimum, what is covered where — every fact traced to how it was checked |
| [symbolication.md](docs/symbolication.md) | what happens to an obfuscated Dart stack trace, and what to do about it |
| [privacy.md](docs/privacy.md) | exactly what leaves the device, from this package and from the vendor SDKs |
| [legal.md](docs/legal.md) | licensing, naming, and the one question to settle before publishing |
| [status.md](docs/status.md) | what is proven and what is not |
| [questions-for-vendor.md](docs/questions-for-vendor.md) | what to ask Tracer support, and what each answer would change |
| [publishing.md](docs/publishing.md) | release order and the pre-publish checklist |
| [contributing.md](docs/contributing.md) | working in this monorepo |

## Development

The packages depend on each other by version and are wired together locally
through `pubspec_overrides.yaml`, which `dart pub publish` ignores.

```sh
make            # list every target
make bootstrap  # pub get in every package
make check      # analyze + test + publish dry-run
```

The `Makefile` also carries the run commands for the example on each platform
(`make example-android`, `example-ios`, `example-web`), which are easy to get
wrong: the Android token comes from the Gradle plugin, iOS takes it through
`--dart-define`, and web needs a Sentry DSN instead. `.vscode/launch.json`
mirrors the same set for anyone launching from the editor.

## License

MIT, see [LICENSE](LICENSE). The vendor SDKs are licensed separately; see
[docs/legal.md](docs/legal.md).
