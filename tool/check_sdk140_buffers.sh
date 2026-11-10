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
# Keep matched SDK pairs: a mixed classpath has not been inspected.
case "$(shasum -a 256 "$commons" | awk '{print $1}')" in
  ee7964358a1385c2fc38d362e7e49aa2e61a1998a3c8992ad4f61f1f03381782)
    verify_hash "$crash" aeffc371b708e60032942074603aeaa1d8aa9c77e0442e332408bf71c46bf6dd ;;
  9cb045087b426cc8215d00556815a5cf0560c18c96fcf91c21ddd59b53fc82ae)
    verify_hash "$crash" d0825dfe7b270ae62b3eb7e120236aec74f07aaff862887127c7633fe923d925 ;;
  3be4caa6cfea92c7f3e44eb191c1ef0a8ad3e9cbc831839aee119fbcdc8a4d67)
    verify_hash "$crash" a97c68cdc9eabce8d04be28eb5ea18b739ed848bdc6f6f50a70cbd4a9b333258
    verify_hash "$base" b0331c5a4eeedf279b2abc80d4ea42067b4e4ea844f90a966b18a4a508e935e6 ;;
  *) echo "Unverified SDK commons artifact: re-audit before updating its hash" >&2; exit 1 ;;
esac
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
