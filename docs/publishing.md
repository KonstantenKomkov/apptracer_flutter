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

`apptracer_flutter_sentry` is **not** in that list and carries
`publish_to: none`. The platforms it exists for — desktop and Aurora OS — are
outside this release and have never been run against a live Tracer project, so
there is nothing to publish it on the strength of. Anyone who needs it can
depend on it from git. Remove the line and add it to the list, after
`apptracer_flutter_platform_interface`, when that changes.

0.1.0 went out on 2026-08-28, in that order. Every package now resolves its
siblings from pub.dev, so the `publish-dry-run` CI job is required rather than
`continue-on-error` — a failure there is a real one.

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
- [ ] `dart pub publish --dry-run` reports no warnings
- [ ] `LICENSE`, `README.md`, `CHANGELOG.md` present
- [ ] `README.md` is the Russian one (pub.dev renders exactly this file);
      `README.en.md` carries the same content in English and the two link
      to each other
- [ ] every public member has a doc comment
- [ ] `topics` set in `pubspec.yaml`
- [ ] no token, DSN or other secret anywhere in the package — check the packed
      file list, not just the source

```sh
cd packages/<package>
dart pub publish --dry-run
dart pub publish
```

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

Below `1.0.0`, a breaking change bumps the **minor** version, which is what
pub.dev treats as breaking for `^0.x` constraints. `1.0.0` waits until a real
Tracer project has confirmed end-to-end delivery on each supported platform;
until then [status.md](status.md) lists what is unproven, and claiming stability
would be a claim nobody has checked.
