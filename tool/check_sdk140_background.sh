#!/usr/bin/env bash
# Supply extracted audited tracer-commons classes.jar and Kotlin stdlib.jar.
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 tracer-commons-classes.jar kotlin-stdlib.jar" >&2
  exit 2
fi
sdk_jar="$1"
kotlin_jar="$2"
actual="$(shasum -a 256 "$sdk_jar" | awk '{print $1}')"
if [[ "$actual" != "ee7964358a1385c2fc38d362e7e49aa2e61a1998a3c8992ad4f61f1f03381782" &&
      "$actual" != "9cb045087b426cc8215d00556815a5cf0560c18c96fcf91c21ddd59b53fc82ae" &&
      "$actual" != "3be4caa6cfea92c7f3e44eb191c1ef0a8ad3e9cbc831839aee119fbcdc8a4d67" ]]; then
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
