#!/usr/bin/env bash
# Standalone JVM check of a plugin classfile JAR built without the vendor SDK.
set -euo pipefail
if [[ $# -ne 4 ]]; then
  echo "Usage: $0 plugin.jar flutter.jar android.jar kotlin-stdlib.jar" >&2
  exit 2
fi
plugin="$1"
flutter="$2"
android_api="$3"
stdlib="$4"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compiled="$(mktemp -d "${TMPDIR:-/tmp}/apptracer-no-sdk.XXXXXX")"
trap 'rm -rf "$compiled"' EXIT
classpath="$compiled:$plugin:$flutter:$android_api:$stdlib"
javac -cp "$classpath" -d "$compiled" \
  "$repo_root/packages/apptracer_flutter_android/android/src/test/java/ru/apptracer/flutter/MissingSdkLifecycleTest.java"
java -cp "$classpath" ru.apptracer.flutter.MissingSdkLifecycleTest
