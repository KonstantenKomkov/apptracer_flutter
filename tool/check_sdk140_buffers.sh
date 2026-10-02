#!/usr/bin/env bash
# Inspected SDK stores; Android API classes are used only for JVM type resolution.
set -euo pipefail
if [[ $# -ne 6 ]]; then
  echo "Usage: $0 commons-classes.jar crash-classes.jar base-classes.jar kotlin-stdlib.jar android.jar javax.inject.jar" >&2
  exit 2
fi
commons="$1"
crash="$2"
base="$3"
stdlib="$4"
android_api="$5"
inject="$6"
verify_hash() {
  if [[ "$(shasum -a 256 "$1" | awk '{print $1}')" != "$2" ]]; then
    echo "Unverified SDK artifact: re-audit diagnostic buffers before updating its hash" >&2
    exit 1
  fi
}
verify_hash "$commons" ee7964358a1385c2fc38d362e7e49aa2e61a1998a3c8992ad4f61f1f03381782
verify_hash "$crash" aeffc371b708e60032942074603aeaa1d8aa9c77e0442e332408bf71c46bf6dd
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compiled="$(mktemp -d "${TMPDIR:-/tmp}/apptracer-buffers.XXXXXX")"
trap 'rm -rf "$compiled"' EXIT
source_root="$repo_root/packages/apptracer_flutter_android/android/src"
classpath="$compiled:$commons:$crash:$base:$stdlib:$android_api:$inject"
javac -cp "$classpath" -d "$compiled" \
  "$source_root/main/java/ru/apptracer/flutter/RevocableExecutor.java" \
  "$source_root/main/java/ru/apptracer/flutter/Sdk140Endpoint.java" \
  "$source_root/main/java/ru/apptracer/flutter/Sdk140DiagnosticBuffers.java" \
  "$source_root/main/java/ru/apptracer/flutter/Sdk140FatalHandler.java" \
  "$source_root/test/java/ru/apptracer/flutter/Sdk140EndpointTest.java" \
  "$source_root/test/java/ru/apptracer/flutter/Sdk140DiagnosticBuffersTest.java" \
  "$source_root/test/java/ru/apptracer/flutter/Sdk140FatalHandlerTest.java"
java -cp "$classpath" ru.apptracer.flutter.Sdk140EndpointTest
java -cp "$classpath" ru.apptracer.flutter.Sdk140DiagnosticBuffersTest

java -cp "$classpath" ru.apptracer.flutter.Sdk140FatalHandlerTest
