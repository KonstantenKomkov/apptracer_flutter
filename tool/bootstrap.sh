#!/usr/bin/env bash
# Resolves dependencies for every package in the monorepo.
set -euo pipefail

cd "$(dirname "$0")/.."

packages=()
while IFS= read -r package_path; do packages+=("$package_path"); done < <(python3 tool/package_catalog.py paths)

for package in "${packages[@]}"; do
  echo "==> pub get $package"
  (cd "$package" && flutter pub get)
done
