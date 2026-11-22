#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
failed=0
if ! git diff --exit-code; then
  echo "Tracked files were modified by the checks." >&2
  failed=1
fi
if ! git diff --cached --exit-code; then
  echo "Staged files differ; run publication checks from a clean commit." >&2
  failed=1
fi
untracked="$(git ls-files --others --exclude-standard)"
if [[ -n "$untracked" ]]; then
  echo "Untracked files left by the checks:" >&2
  echo "$untracked" >&2
  failed=1
fi
exit "$failed"
