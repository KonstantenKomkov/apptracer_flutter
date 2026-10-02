#!/usr/bin/env bash
# Host checks for the version-pinned iOS storage adapter; run on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/apptracer-storage.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
swiftc \
  packages/apptracer_flutter_ios/ios/apptracer_flutter_ios/Sources/apptracer_flutter_ios/CollectionStorage.swift \
  packages/apptracer_flutter_ios/test/native/storage_test.swift \
  -o "$work_dir/check"
"$work_dir/check"
