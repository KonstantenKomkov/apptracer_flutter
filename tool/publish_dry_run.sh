#!/usr/bin/env bash
set -euo pipefail
package="$1"
log="$(mktemp "${TMPDIR:-/tmp}/apptracer-publish.XXXXXX")"
trap 'rm -f "$log"' EXIT
status=0
(cd "$package" && dart pub publish --dry-run) >"$log" 2>&1 || status=$?
cat "$log"
if [[ "$status" == 0 ]]; then exit 0; fi
if [[ "$status" == 65 && "$package" == packages/apptracer_flutter_desktop ]] &&
   grep -q 'Your dependency on "sentry_flutter" should allow more than one version' "$log" &&
   grep -Eq '^  +sentry_flutter: \^10\.6\.0$' "$log" &&
   grep -Eq '^Package has 1 warning( and [0-9]+ hints?)?\.$' "$log"; then
  echo "Expected warning: sentry_flutter remains exactly pinned at 10.6.0 for native lifecycle compatibility."
  exit 0
fi
exit "$status"
