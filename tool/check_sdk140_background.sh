#!/usr/bin/env bash
# Supply extracted tracer-commons 1.4.0 classes.jar and Kotlin stdlib.jar.
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 tracer-commons-1.4.0-classes.jar kotlin-stdlib.jar" >&2
  exit 2
fi
sdk_jar="$1"
kotlin_jar="$2"
expected="ee7964358a1385c2fc38d362e7e49aa2e61a1998a3c8992ad4f61f1f03381782"
actual="$(shasum -a 256 "$sdk_jar" | awk '{print $1}')"
if [[ "$actual" != "$expected" ]]; then
  echo "Unverified SDK artifact: re-audit its background queue before updating the hash" >&2
  exit 1
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compiled="$(mktemp -d "${TMPDIR:-/tmp}/apptracer-sdk140.XXXXXX")"
trap 'rm -rf "$compiled"' EXIT
source_root="$repo_root/packages/apptracer_flutter_android/android/src"
javac -d "$compiled" \
  "$source_root/main/java/ru/apptracer/flutter/RevocableExecutor.java" \
  "$source_root/main/java/ru/apptracer/flutter/Sdk140BackgroundExecutor.java" \
  "$source_root/test/java/ru/apptracer/flutter/Sdk140BackgroundExecutorTest.java"
java -cp "$compiled:$sdk_jar:$kotlin_jar" ru.apptracer.flutter.Sdk140BackgroundExecutorTest
