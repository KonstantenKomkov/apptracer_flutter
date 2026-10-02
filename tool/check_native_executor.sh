#!/usr/bin/env bash
# Pure JVM lifecycle checks; no Flutter/Android runtime or Maven download needed.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
executor_classes="$(mktemp -d "${TMPDIR:-/tmp}/apptracer-executor.XXXXXX")"
trap 'rm -rf "$executor_classes"' EXIT
javac -d "$executor_classes" \
  "$repo_root/packages/apptracer_flutter_android/android/src/main/java/ru/apptracer/flutter/RevocableExecutor.java" \
  "$repo_root/packages/apptracer_flutter_android/android/src/test/java/ru/apptracer/flutter/RevocableExecutorTest.java" \
  "$repo_root/packages/apptracer_flutter_android/android/src/main/java/ru/apptracer/flutter/DiagnosticFiles.java" \
  "$repo_root/packages/apptracer_flutter_android/android/src/test/java/ru/apptracer/flutter/DiagnosticFilesTest.java"
java -cp "$executor_classes" ru.apptracer.flutter.RevocableExecutorTest

java -cp "$executor_classes" ru.apptracer.flutter.DiagnosticFilesTest
