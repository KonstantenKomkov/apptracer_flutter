#!/usr/bin/env bash
# Everything CI runs, in the same order, so a green run here means a green CI.
set -euo pipefail

cd "$(dirname "$0")/.."

packages=(
  packages/apptracer_flutter_platform_interface
  packages/apptracer_flutter_http
  packages/apptracer_flutter_sentry
  packages/apptracer_flutter_android
  packages/apptracer_flutter_ios
  packages/apptracer_flutter_web
  packages/apptracer_flutter
)

failed=0

for package in "${packages[@]}"; do
  echo
  echo "==> $package"
  (
    cd "$package"
    flutter pub get >/dev/null
    dart format --output=none --set-exit-if-changed .
    flutter analyze --fatal-infos
    if [ ! -d test ]; then
      :
    elif [ "$package" = "packages/apptracer_flutter_web" ]; then
      # The web package's tests exercise browser-only code paths.
      flutter test --platform chrome --reporter=compact
    else
      flutter test --reporter=compact
    fi
  ) || failed=1
done

echo
echo "==> example"
(
  cd packages/apptracer_flutter/example
  flutter pub get >/dev/null
  dart format --output=none --set-exit-if-changed lib test integration_test test_driver
  flutter analyze --fatal-infos
  flutter test --reporter=compact
) || failed=1

echo
echo "==> publish dry-run"
# Runs without the local overrides, so it fails loudly if a package would be
# published with a dependency that does not exist on pub.dev yet. Before the
# first release that is expected; see docs/publishing.md.
for package in "${packages[@]}"; do
  echo "--> $package"
  (cd "$package" && dart pub publish --dry-run) || failed=1
done

exit "$failed"
