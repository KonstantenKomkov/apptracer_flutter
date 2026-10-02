#!/usr/bin/env bash
# Run against a classfile JAR produced by R8 with the real consumer/vendor rules.
# This checks Java reflection and queue revocation, not an Android APK or JNI run.
set -euo pipefail
if [[ $# -ne 4 ]]; then
  echo "Usage: $0 r8-output.jar kotlin-stdlib.jar android.jar javax.inject.jar" >&2
  exit 2
fi
optimized="$1"
stdlib="$2"
android_api="$3"
inject="$4"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compiled="$(mktemp -d "${TMPDIR:-/tmp}/apptracer-reflection.XXXXXX")"
trap 'rm -rf "$compiled"' EXIT
source_root="$repo_root/packages/apptracer_flutter_android/android/src/test/java/ru/apptracer/flutter"
classpath="$compiled:$optimized:$stdlib:$android_api:$inject"
javac -cp "$classpath" -d "$compiled" \
  "$source_root/RevocableExecutorTest.java" \
  "$source_root/Sdk140BackgroundExecutorTest.java" \
  "$source_root/DiagnosticFilesTest.java" \
  "$source_root/Sdk140ReflectionTest.java" \
  "$source_root/Sdk140DiagnosticBuffersTest.java" \
  "$source_root/Sdk140FatalHandlerTest.java"
for check in RevocableExecutorTest Sdk140BackgroundExecutorTest DiagnosticFilesTest Sdk140ReflectionTest Sdk140DiagnosticBuffersTest Sdk140FatalHandlerTest; do
  java -cp "$classpath" "ru.apptracer.flutter.$check"
done
