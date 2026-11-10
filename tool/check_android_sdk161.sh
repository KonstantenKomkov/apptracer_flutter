#!/usr/bin/env bash
# Unit tests and clean R8 releases with/without SDK. Never installs or uploads.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --fresh-cache ) ]]; then
  echo "Usage: $0 [--fresh-cache]" >&2
  exit 2
fi
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/apptracer-sdk161-build.XXXXXX")"
echo "Android verification artifacts: $verification_dir"
gradle_args=(--console=plain --no-build-cache --no-configuration-cache
  -PskipDependencyChecks=true -Ptarget-platform=android-arm64
  --project-cache-dir "$verification_dir/project-cache"
  -I "$repo_root/tool/android_no_upload.init.gradle")
if [[ $# -eq 1 ]]; then
  # Do not seed dependency/transform caches: this is the Central migration test.
  wrapper_distributions="${GRADLE_USER_HOME:-$HOME/.gradle}/wrapper"
  export GRADLE_USER_HOME="$verification_dir/gradle-home"
  mkdir -p "$GRADLE_USER_HOME"
  # The Gradle executable distribution is not a Maven dependency cache.
  if [[ -d "$wrapper_distributions" ]]; then
    ln -s "$wrapper_distributions" "$GRADLE_USER_HOME/wrapper"
  fi
fi
# The example still requires both values until mappings configuration task 18.
# These placeholders cannot upload: vendor upload task types are disabled above.
export TRACER_APP_TOKEN=android-sdk161-build-placeholder
export TRACER_PLUGIN_TOKEN=android-sdk161-plugin-placeholder
cd "$repo_root/packages/apptracer_flutter/example"
# Flutter must generate the release registrant, excluding dev-only native
# plugins such as integration_test, before Gradle compiles the application.
# Do not pass --no-pub: Flutter then skips registrant generation too.
flutter build apk --release --config-only --target-platform=android-arm64 \
  --android-skip-build-dependency-validation
cd android
./gradlew "${gradle_args[@]}" clean :apptracer_flutter_android:testDebugUnitTest \
  :app:assembleRelease -Ptracer.enabled=true -Ptracer.deferred=false
cp -R ../build/apptracer_flutter_android/test-results/testDebugUnitTest \
  "$verification_dir/unit-results"
cp ../build/app/outputs/apk/release/app-release.apk "$verification_dir/with-sdk.apk"
cp ../build/app/outputs/mapping/release/mapping.txt "$verification_dir/with-sdk-mapping.txt"
./gradlew "${gradle_args[@]}" clean :app:assembleRelease \
  -Ptracer.enabled=false -Ptracer.deferred=false
cp ../build/app/outputs/apk/release/app-release.apk "$verification_dir/without-sdk.apk"
cp ../build/app/outputs/mapping/release/mapping.txt "$verification_dir/without-sdk-mapping.txt"
echo "Unit tests and both release/R8 builds passed: $verification_dir"
