# Publishing

## Before the first release — settle this

**The licence has been read** (edition of 29 May 2025) and does not prohibit
publishing this wrapper. The full reading, clause by clause, is in
[legal.md](legal.md).

One point is left open: clause 4.2.4 forbids using the Library "as the basis for
a product containing the same functionality", and while that plainly targets a
rival SDK rather than an integration adapter, it is a reading rather than a
certainty. Question 2 in [questions-for-vendor.md](questions-for-vendor.md) asks
the vendor to confirm it.

- [ ] the vendor's answer to question 2 confirms the reading

**If it does not, stop and do not publish.** The work still stands as a private
integration.

## Prove it works first

Publishing before a real Tracer project has confirmed delivery would ship a
crash reporter nobody has watched report a crash. Work through
[live-verification-plan.md](live-verification-plan.md) and close its results
table before anything below.

## Set the repository URL first

Every `pubspec.yaml` currently points `repository`, `issue_tracker` and
`documentation` at `https://github.com/komkovkonstantin/apptracer_flutter`, and
the README files link to `docs/` through the same URL. **That URL is a
placeholder.** Publishing with links that 404 costs pub.dev points and, worse,
sends users nowhere when they hit a problem.

```sh
# From the repository root, once the real remote exists:
git grep -l 'github.com/komkovkonstantin/apptracer_flutter' \
  | xargs sed -i '' 's|github.com/komkovkonstantin/apptracer_flutter|github.com/<owner>/<repo>|g'
```

Also replace the placeholder author in
`packages/apptracer_flutter_ios/ios/apptracer_flutter_ios.podspec`.

## Order

Packages depend on each other by version, so they go out leaves first. Each step
has to be on pub.dev before the next resolves.

1. `apptracer_flutter_platform_interface`
2. `apptracer_flutter_http`
3. `apptracer_flutter_android`
4. `apptracer_flutter_ios`
5. `apptracer_flutter_web`
6. `apptracer_flutter`

`dart pub publish --dry-run` fails for a package whose siblings are not yet
published. Before the first release that is expected, which is why the CI job
is `continue-on-error`. Make it required once 0.1.0 is out.

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
not in the example, not in a Gradle file. The example reads
`TRACER_APP_TOKEN`, `TRACER_PLUGIN_TOKEN` and `TRACER_DSN` from the environment
and refuses to build with `-Ptracer.enabled=true` when they are absent, rather
than producing a release whose crashes silently go nowhere.

Before a release, confirm the packed archive is clean:

```sh
dart pub publish --dry-run 2>&1 | sed -n '/Package has/,$p'
git grep -nE '(appToken|pluginToken|dsn)\s*[:=]\s*["'\''][A-Za-z0-9]{8,}' -- . || echo "no literal secrets"
```

## Version policy

Below `1.0.0`, a breaking change bumps the **minor** version, which is what
pub.dev treats as breaking for `^0.x` constraints. `1.0.0` waits until a real
Tracer project has confirmed end-to-end delivery on each supported platform;
until then [status.md](status.md) lists what is unproven, and claiming stability
would be a claim nobody has checked.
