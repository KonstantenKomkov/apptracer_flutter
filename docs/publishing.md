# Publishing

## Before the first release — settled

**The licence has been read** (edition of 29 May 2025) and does not prohibit
publishing this wrapper. The full reading, clause by clause, is in
[legal.md](legal.md).

The one point that was open — clause 4.2.4, which forbids using the Library "as
the basis for a product containing the same functionality" — was put to the
vendor as question 2.

- [x] the vendor's answer to question 2 confirms the reading — **2026-08-27, no
  objection**, to the reading or to the name. Recorded in
  [legal.md](legal.md); the wording is summarised there rather than quoted,
  which is worth fixing if the message can still be pasted in.

## Prove it works first

Publishing before a real Tracer project has confirmed delivery would ship a
crash reporter nobody has watched report a crash. Work through
[live-verification-plan.md](live-verification-plan.md) and close its results
table before anything below.

## The repository URL — done 2026-08-27

Every `pubspec.yaml` used to point `repository`, `issue_tracker` and
`documentation` at `https://github.com/komkovkonstantin/apptracer_flutter`,
which was a placeholder: the real remote is
`https://github.com/KonstantenKomkov/apptracer_flutter`. Publishing with links
that 404 costs pub.dev points and, worse, sends users nowhere when they hit a
problem. Replaced across 28 files, along with the placeholder author in
`packages/apptracer_flutter_ios/ios/apptracer_flutter_ios.podspec`
(`noreply@example.com` → the address the commits already carry).

If the repository ever moves:

```sh
git grep -l 'github.com/KonstantenKomkov/apptracer_flutter' \
  | xargs sed -i '' 's|github.com/KonstantenKomkov/apptracer_flutter|github.com/<owner>/<repo>|g'
```

## Order

Packages depend on each other by version, so they go out leaves first. Each step
has to be on pub.dev before the next resolves.

1. `apptracer_flutter_platform_interface`
2. `apptracer_flutter_http`
3. `apptracer_flutter_android`
4. `apptracer_flutter_ios`
5. `apptracer_flutter_web`
6. `apptracer_flutter`

`apptracer_flutter_sentry` is the legacy manual transport and remains
`publish_to: none`. Do not publish it as the new desktop backend.
The optional `apptracer_flutter_desktop` is a stable **1.0.0** package using
the official Sentry SDK for Windows, macOS and Ubuntu Linux. For this release,
publish facade **1.0.0** first, then desktop **1.0.0**. The facade includes the
obfuscated `FlutterError` type-name fix. Platform-interface, Android, iOS, Web
and HTTP packages retain their compatible published versions.

Keep the exact `sentry_flutter: 9.30.1` dependency until the version-specific
integration has been re-audited. Pub reports one intentional tight-constraint
warning for desktop; no other warnings are accepted.

Earlier Ubuntu/Windows acceptance used hosted facade 0.2.1 and an isolated
0.2.2 candidate. Those historical records describe the tested builds; the final
release is 1.0.0 for both facade and desktop. See
[desktop-migration.md](desktop-migration.md) for platform installation and
consumer checks. After publication, run the Windows consumer with
`--hosted-desktop 1.0.0 --facade-version 1.0.0` to verify hosted resolution,
release compilation and runtime behavior without source dependencies.

0.1.0 went out on 2026-08-28, in that order. The required `publish-dry-run` CI
job checks archive contents and package metadata using local overrides. It does
not prove that a consumer can resolve the new versions from pub.dev.

Only the packages that changed go out after that, in the same leaves-first
order. `apptracer_flutter_android` 0.1.1 went out alone on 2026-08-30.

CI does not build iOS on every push any more. That job needs a macOS runner,
which bills at ten times a Linux one, and it was two thirds of this
repository's Actions spend while the iOS half of the package changed a few
times a year. It lives in `.github/workflows/ios.yml` and runs when files under
`packages/apptracer_flutter_ios/` or the example's `ios/` change — a release of
that package always edits its `pubspec.yaml`, so a release commit still builds
it. Run the workflow by hand (Actions → iOS → Run workflow) if you want it
against a change it does not match.

The `vX.Y.Z` tag numbers the **release event**, not any one package: packages
version independently, and after 0.1.0 they no longer share a number. The
CHANGELOG links compare two event tags, which is why an entry for 0.1.1 can sit
between `v0.1.1` and `v0.1.2`.

## Checklist per package

- [ ] `CHANGELOG.md` has an entry for the version, dated, in Keep a Changelog form
- [ ] the version in `pubspec.yaml` matches it
- [ ] `flutter analyze --fatal-infos` is clean
- [ ] `flutter test` passes
- [ ] `dart format --set-exit-if-changed .` is clean
- [ ] `dart pub publish --dry-run` reports no unexpected warnings (the
      desktop adapter's exact SDK pin is the documented exception above)
- [ ] hosted dependencies resolve without `pubspec_overrides.yaml`, after the
      required sibling versions have been published
- [ ] `LICENSE`, `README.md`, `CHANGELOG.md` present
- [ ] `README.md` is the Russian one (pub.dev renders exactly this file);
      `README.en.md` carries the same content in English and the two link
      to each other
- [ ] every public member has a doc comment
- [ ] `topics` set in `pubspec.yaml`
- [ ] no token, DSN or other secret anywhere in the package — check the packed
      file list, not just the source

```sh
# Use an export of the release commit so local overrides cannot affect resolution.
release_checkout="$(mktemp -d)"
git archive HEAD | tar -x -C "$release_checkout"
find "$release_checkout/packages" -name pubspec_overrides.yaml -delete
cd "$release_checkout/packages/<package>"
flutter pub get --no-example
dart pub publish --dry-run
dart pub publish
```

Repeat the package commands in the order above, waiting until each dependency
is available from pub.dev. Do not add overrides to work around a missing release.
Resolve the example with `flutter pub get` after the facade is published: it
depends on that same version, so resolving it before publication would fail.
The facade's `.pubignore` also excludes the example's monorepo overrides from
the archive; ignore rules are described in the
[Dart publishing documentation](https://dart.dev/tools/pub/publishing#what-files-are-published).

## Stable 0.2.0 — 2026-10-03

All six packages in the publication order use `0.2.0` and matching `^0.2.0`
internal constraints. This is a stable minor release, with no prerelease suffix.
The local Sentry transport is version-aligned but remains `publish_to: none`.

Published to pub.dev on 2026-10-03 from `v0.2.0` (`4345873`), in the order above.
Each package passed hosted dependency resolution without local overrides and a
dry run with zero warnings or hints before upload. CI and iOS builds passed for
the release commit.
The downloaded archives' SHA-256 hashes matched pub.dev metadata, and every
packaged file matched the release tag. The example resolved all six `0.2.0`
packages from pub.dev without overrides and passed `flutter analyze --fatal-infos`.
The entry point is [apptracer_flutter 0.2.0](https://pub.dev/packages/apptracer_flutter/versions/0.2.0).

The release adds explicit collection start and revocation with cleanup, backed
by Android Tracer 1.4.0 and OKTracer 1.5.2. Automatic startup remains the default;
applications opting into deferred Android startup must remove both startup
providers. After native collection has been stopped, re-consent requires a
process restart. iOS symbol uploads now require `--app-name`; `--build` is no
longer accepted. See each package's dated CHANGELOG for the full migration notes.

Device/browser verification and remaining symbolication limits are recorded in
[native-collection-consent.md](native-collection-consent.md). A release commit or
tag records the prepared source; publication is complete only once all six
versions are available on pub.dev.

## Stable 0.2.1 — 2026-10-16

Published from `v0.2.1` (`31a4f5b`) in dependency order:

1. [apptracer_flutter_android 0.2.1](https://pub.dev/packages/apptracer_flutter_android/versions/0.2.1)
2. [apptracer_flutter 0.2.1](https://pub.dev/packages/apptracer_flutter/versions/0.2.1)

Other runtime packages remain at 0.2.0. This release updates the Android build
target and example Gradle plugin to Tracer 1.5.2, retains the vendor Nexus
repository, and adds opt-in Android 12+ tombstones. The deferred adapter accepts
1.4.0 and 1.5.2. See [the SDK audit](android-sdk-1.5.2.md) for the precise
validation scope; live tombstone delivery has not been verified.

Publication used a clean export of the release commit with every
`pubspec_overrides.yaml` removed. Both packages passed hosted dependency
resolution, analysis, tests and publication dry-runs with zero warnings.
The facade's pre-publication analysis covered `lib` and `test`; its example
requires the facade's own published version. Generated test output was removed
before packing. [Release CI](https://github.com/KonstantenKomkov/apptracer_flutter/actions/runs/38866697243)
passed all jobs.

After publication the example resolved the facade and Android implementation
at 0.2.1 from pub.dev without overrides and passed analysis and its widget test.
`flutter pub upgrade` refreshed cached version metadata after pub.dev indexing.

Downloaded archive SHA-256 values match pub.dev metadata. Every packaged file
matches the release commit (37 Android files and 109 facade files):

| Package | Archive SHA-256 |
|---|---|
| `apptracer_flutter_android` | `9f56a0b62ee80f486693dd0e86473eb8389bbd79bfb86ca5810d84f39fabdc13` |
| `apptracer_flutter` | `41e59a0fa088b31778b061ab1236dabfc225ed1f3519f046184ca2099058e472` |

## Stable 1.0.0 — 2026-10-24

Published from `e4b0e515abd0c40631f8d6d48004bf08b68ec036` (`v1.0.0`),
after merging [Windows PR #3](https://github.com/KonstantenKomkov/apptracer_flutter/pull/3):

1. [apptracer_flutter 1.0.0](https://pub.dev/packages/apptracer_flutter/versions/1.0.0)
2. [apptracer_flutter_desktop 1.0.0](https://pub.dev/packages/apptracer_flutter_desktop/versions/1.0.0)

Both are stable releases. Desktop remains an optional dependency for Windows,
macOS and Ubuntu Linux. The existing Android 0.2.1, iOS/Web/interface/HTTP 0.2.0
packages retain their versions. Facade 1.0.0 preserves `FlutterError` type names
under obfuscation and excludes generated test output from standalone archives.

Publication used a clean Git export outside the repository, on drive D, without
monorepo overrides. Both packages passed formatting and analysis; the facade
passed 82 tests and desktop passed 20 Windows-applicable tests (6 platform skips).
The facade dry-run had zero warnings. Desktop retained exactly one documented
warning for its audited `sentry_flutter: 9.30.1` pin.

After publication, both examples resolved their dependencies without monorepo
overrides and passed analysis and widget tests. The facade example uses hosted
1.0.0; the desktop example keeps its normal relative adapter dependency.

Downloaded archives match pub.dev SHA-256 metadata and every packaged file
matches the release export:

| Package | Files | Archive SHA-256 |
|---|---:|---|
| `apptracer_flutter` | 110 | `38f73f1530611ff39884518ac0eb1a561efa65d7e5111559cbf79c452a7c5ea6` |
| `apptracer_flutter_desktop` | 109 | `d11561dd46171ae82d62a8311e1b972d64787644c0f9b6b02f2c7e0403fb0870` |

After publication, a newly generated Windows x64 consumer resolved **all**
Tracer packages from pub.dev, with facade and desktop exactly 1.0.0 and no path,
Git or override dependencies. Analysis, obfuscated release build, relocated
runtime with restricted PATH, three-event delivery, filtering/deduplication,
exact-build Dart source frames, stable `FlutterError` and stop/clear passed.
The bundle includes the native crash handler and app-local MSVC runtime.
This checks hosted installation; earlier full native/live/clean-VM acceptance
remains recorded in [windows-local-acceptance.md](windows-local-acceptance.md).

Consumer bundle SHA-256: `7d8e0fa411d4520fe0a12e47957a7332e65da3e03b9d84f07e61291c2001ed65`.
Local receipts: `build/stable-1.0.0/` and
`build/windows-consumer-published/report.json`.
The consumer harness never publishes, so its `published:false` field describes
the check's actions, not whether its hosted dependencies exist.

## Secrets

No credential of any kind belongs in this repository — not in a test fixture,
not in the example, not in a Gradle file. The example reads `TRACER_APP_TOKEN`
and `TRACER_PLUGIN_TOKEN` from the environment and refuses to build with
`-Ptracer.enabled=true` when they are absent, rather than producing a release
whose crashes silently go nowhere.

Of the two, only `pluginToken` is a secret. `appToken` ships inside the
application — in an Android release it is in `classes.dex` and `resources.arsc`,
put there by the Gradle plugin — so keeping it out of the repository is tidiness
rather than protection. `pluginToken` signs uploads, never reaches the app, and
is the one that matters.

Before a release, confirm the packed archive is clean:

```sh
dart pub publish --dry-run 2>&1 | sed -n '/Package has/,$p'
git grep -nE '(pluginToken|appToken)\s*[:=]\s*["'\''][A-Za-z0-9]{8,}' -- . || echo "no literal secrets"
```

## Version policy

Starting with stable 1.0.0, incompatible public API changes require a major
version, compatible features a minor version and fixes a patch version. Packages
version independently. Desktop is an optional stable package; its tested OS and
architecture scope and service limitations remain documented in
[status.md](status.md) and [platform-matrix.md](platform-matrix.md).
