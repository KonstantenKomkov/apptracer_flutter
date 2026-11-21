#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root/packages/apptracer_flutter_platform_interface"
dart pub get >/dev/null
dart run pigeon \
  --input pigeon/tracer_api.dart \
  --dart_out lib/src/pigeon/tracer_api.dart \
  --kotlin_out ../apptracer_flutter_android/android/src/main/kotlin/ru/apptracer/flutter/TracerApi.kt \
  --kotlin_package ru.apptracer.flutter \
  --swift_out ../apptracer_flutter_ios/ios/apptracer_flutter_ios/Sources/apptracer_flutter_ios/TracerApi.swift
dart format lib/src/pigeon/tracer_api.dart
if [[ "${1:-}" == "--check" ]]; then
  git diff --exit-code -- \
    packages/apptracer_flutter_platform_interface/lib/src/pigeon/tracer_api.dart \
    packages/apptracer_flutter_android/android/src/main/kotlin/ru/apptracer/flutter/TracerApi.kt \
    packages/apptracer_flutter_ios/ios/apptracer_flutter_ios/Sources/apptracer_flutter_ios/TracerApi.swift
fi
