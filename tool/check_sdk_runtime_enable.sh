#!/usr/bin/env bash
# Run a compiled current adapter against each independently audited SDK runtime.
# The second argument contains matched commons/crash/base/manifest JARs plus
# Kotlin stdlib, javax.inject and android.jar, separated by the platform's ':' separator.
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 compiled-plugin.jar audited-runtime-classpath" >&2
  exit 2
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compiled="$(mktemp -d "${TMPDIR:-/tmp}/apptracer-enable.XXXXXX")"
trap 'rm -rf "$compiled"' EXIT
classpath="$compiled:$1:$2"
javac -cp "$classpath" -d "$compiled" \
  "$repo_root/packages/apptracer_flutter_android/android/src/test/java/ru/apptracer/flutter/SdkRuntimeEnableTest.java"
java -cp "$classpath" ru.apptracer.flutter.SdkRuntimeEnableTest
