#!/usr/bin/env bash
# Resolves dependencies for every package in the monorepo.
set -euo pipefail

cd "$(dirname "$0")/.."

paths="$(python3 tool/package_catalog.py paths)"
while IFS= read -r package; do
  echo "==> pub get $package"
  (cd "$package" && flutter pub get)
done <<< "$paths"
