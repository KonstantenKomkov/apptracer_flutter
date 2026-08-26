#!/usr/bin/env bash
# Resolves dependencies for every package in the monorepo.
set -euo pipefail

cd "$(dirname "$0")/.."

# Order matters only for readability: pubspec_overrides.yaml wires the packages
# to each other by path, so pub never reaches pub.dev for them.
packages=(
  packages/apptracer_flutter_platform_interface
  packages/apptracer_flutter_http
  packages/apptracer_flutter_sentry
  packages/apptracer_flutter_android
  packages/apptracer_flutter_ios
  packages/apptracer_flutter_web
  packages/apptracer_flutter
  packages/apptracer_flutter/example
)

for package in "${packages[@]}"; do
  echo "==> pub get $package"
  (cd "$package" && flutter pub get)
done
