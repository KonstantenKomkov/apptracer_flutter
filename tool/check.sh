#!/usr/bin/env bash
# Dart checks from the shared catalog; device/live acceptance runs separately.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=full
case "${1:-}" in
  '' ) ;;
  --analyze-only ) mode=analyze ;;
  --test-only ) mode=test ;;
  * ) echo "Usage: $0 [--analyze-only|--test-only]" >&2; exit 2 ;;
esac

paths="$(python3 tool/package_catalog.py paths)"
passed=()
failed=()
skipped=("device/live acceptance and platform release workflows")

record() {
  local label="$1"
  shift
  echo "==> $label"
  if "$@"; then
    passed+=("$label")
  else
    failed+=("$label")
  fi
}

check_package() {
  local package="$1"
  (cd "$package" && dart pub get >/dev/null) || return 1
  if [[ "$mode" == full ]]; then
    (cd "$package" && dart format --output=none --set-exit-if-changed .) || return 1
  fi
  if [[ "$mode" != test ]]; then
    (cd "$package" && flutter analyze --no-pub --fatal-infos) || return 1
  fi
  if [[ "$mode" != analyze ]]; then
    python3 tool/test_package.py "$package" --coverage || return 1
  fi
}

if [[ "$mode" == full ]]; then
  record native-executor bash tool/check_native_executor.sh
  if [[ "$(uname -s)" == Darwin ]]; then
    record ios-storage bash tool/check_ios_storage.sh
  else
    skipped+=("ios-storage (requires macOS)")
  fi
fi

package_failed=false
while IFS= read -r package; do
  before=${#failed[@]}
  record "$package" check_package "$package"
  if (( ${#failed[@]} > before )); then package_failed=true; fi
done <<< "$paths"

if [[ "$mode" != analyze ]]; then
  if [[ "$package_failed" == true ]]; then
    skipped+=("combined coverage (package checks failed)")
  else
    record coverage python3 tool/coverage_report.py
  fi
fi
if [[ "$mode" == full ]]; then
  publishable="$(python3 tool/package_catalog.py publish)"
  while IFS= read -r package; do
    record "publish:$package" bash tool/publish_dry_run.sh "$package"
  done <<< "$publishable"
  record source-tree bash tool/check_git_clean.sh
fi

echo "==> summary"
echo "passed: ${passed[*]:-none}"
echo "failed: ${failed[*]:-none}"
echo "skipped: ${skipped[*]}"
(( ${#failed[@]} == 0 ))
