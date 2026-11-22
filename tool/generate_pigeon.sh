#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
packages="$repo_root/packages"
interface="$packages/apptracer_flutter_platform_interface"
dart_out="$interface/lib/src/pigeon/tracer_api.dart"
kotlin_out="$packages/apptracer_flutter_android/android/src/main/kotlin/ru/apptracer/flutter/TracerApi.kt"
swift_out="$packages/apptracer_flutter_ios/ios/apptracer_flutter_ios/Sources/apptracer_flutter_ios/TracerApi.swift"

cd "$repo_root/tool/pigeon"
dart pub get --enforce-lockfile >/dev/null
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dart run pigeon \
  --input tracer_api.dart --package_name apptracer_flutter_platform_interface \
  --dart_out "$tmp/tracer_api.dart" \
  --kotlin_out "$tmp/TracerApi.kt" --kotlin_package ru.apptracer.flutter \
  --swift_out "$tmp/TracerApi.swift"
dart format "$tmp/tracer_api.dart"

for target in "$dart_out" "$kotlin_out" "$swift_out"; do
  generated="$tmp/${target##*/}"
  if [[ "${1:-}" == "--check" ]]; then
    diff -u "$target" "$generated"
  else
    cp "$generated" "$target"
  fi
done
