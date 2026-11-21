#!/usr/bin/env bash
# Predictable Dart checks from the shared catalog; native/runtime jobs stay explicit.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=full
case "${1:-}" in
  '' ) ;;
  --analyze-only ) mode=analyze ;;
  --test-only ) mode=test ;;
  * ) echo "Usage: $0 [--analyze-only|--test-only]" >&2; exit 2 ;;
esac

packages=()
while IFS= read -r package_path; do packages+=("$package_path"); done < <(python3 tool/package_catalog.py paths)
failed=0
passed=()
failed_packages=()
skipped=()

if [[ "$mode" == full ]]; then
  echo "==> native storage helpers"
  bash tool/check_native_executor.sh || failed=1
  if [[ "$(uname -s)" == "Darwin" ]]; then
    bash tool/check_ios_storage.sh || failed=1
  else
    skipped+=("ios-storage(non-macOS)")
  fi
fi

for package in "${packages[@]}"; do
  echo
  echo "==> $package"
  (
    cd "$package"
    flutter pub get >/dev/null || exit 1
    if [[ "$mode" == full ]]; then
      dart format --output=none --set-exit-if-changed . || exit 1
    fi
    if [[ "$mode" == full || "$mode" == analyze ]]; then
      flutter analyze --fatal-infos || exit 1
    fi
    if [[ "$mode" == full || "$mode" == test ]]; then
      if [ ! -d test ]; then
        :
      elif [ "$package" = "packages/apptracer_flutter_web" ]; then
        flutter test --platform chrome --reporter=compact || exit 1
      else
        flutter test --reporter=compact --coverage || exit 1
        if [ "$package" = "packages/apptracer_flutter_http" ]; then
          flutter test --platform chrome --reporter=compact \
            test/collection_lifecycle_test.dart test/tracer_batch_item_test.dart || exit 1
        fi
      fi
    fi
  ) && passed+=("$package") || {
    failed_packages+=("$package")
    failed=1
  }
done

if [[ "$mode" == full || "$mode" == test ]]; then
  echo
  echo "==> combined coverage"
  python3 tool/coverage_report.py || failed=1
fi

if [[ "$mode" == full ]]; then
  echo
  echo "==> publish dry-run"
  publishable=()
  while IFS= read -r package_path; do publishable+=("$package_path"); done < <(python3 tool/package_catalog.py publish)
  for package in "${publishable[@]}"; do
    echo "--> $package"
    bash tool/publish_dry_run.sh "$package" || failed=1
  done
fi

echo
echo "==> source tree unchanged"
bash tool/check_git_clean.sh || failed=1

echo
echo "==> summary"
echo "passed: ${passed[*]:-none}"
echo "failed: ${failed_packages[*]:-none}"
echo "skipped: native device/live acceptance and platform release workflows (explicit jobs)${skipped[*]:+; ${skipped[*]}}"
exit "$failed"
