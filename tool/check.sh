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

bash tool/check_native_executor.sh || failed=1
if [[ "$(uname -s)" == "Darwin" ]]; then
  bash tool/check_ios_storage.sh || failed=1
fi

for package in "${packages[@]}"; do
  echo
  echo "==> $package"
  (
    cd "$package"
    # The surrounding || disables bash's implicit errexit inside this group.
    # Preserve each failure explicitly instead of letting a later test hide it.
    flutter pub get >/dev/null || exit 1
    dart format --output=none --set-exit-if-changed . || exit 1
    flutter analyze --fatal-infos || exit 1
    if [ ! -d test ]; then
      :
    elif [ "$package" = "packages/apptracer_flutter_web" ]; then
      # The web package's tests exercise browser-only code paths.
      flutter test --platform chrome --reporter=compact || exit 1
    else
      flutter test --reporter=compact || exit 1
      if [ "$package" = "packages/apptracer_flutter_http" ]; then
        flutter test --platform chrome --reporter=compact \
          test/collection_lifecycle_test.dart test/tracer_batch_item_test.dart || exit 1
      fi
    fi
  ) || failed=1
done

echo
echo "==> example"
(
  cd packages/apptracer_flutter/example
  flutter pub get >/dev/null || exit 1
  dart format --output=none --set-exit-if-changed lib test integration_test test_driver || exit 1
  flutter analyze --fatal-infos || exit 1
  flutter test --reporter=compact || exit 1
) || failed=1

echo
echo "==> publish dry-run"
# Checks the package contents in the current checkout. Local overrides remain
# active; this does not prove resolution against already published dependencies.
# Dirty tracked files also cause pub's publication warning. See docs/publishing.md.
for package in "${packages[@]}"; do
  echo "--> $package"
  (cd "$package" && dart pub publish --dry-run) || failed=1
done

exit "$failed"
