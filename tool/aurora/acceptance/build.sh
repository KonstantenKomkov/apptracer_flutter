#!/bin/sh
# Build a test-only RPM in a new directory. Run from any directory in the checkout.
set -eu
fixture=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$fixture/../../.." && pwd)
plugin="$repo/aurora/apptracer_flutter_aurora"
flutter_bin=${AURORA_FLUTTER_BIN:-flutter-aurora}
mkdir -p "$repo/build"
work=$(mktemp -d "$repo/build/aurora-runner-XXXXXX")
mkdir -p "$work/example/aurora"
cp "$plugin/example/pubspec.yaml" "$work/example/"
cp -R "$plugin/example/lib" "$work/example/"
cp -R "$plugin/example/aurora/icons" "$work/example/aurora/"
cd "$work/example"
python3 - "$plugin" <<'PY'
import json
import sys
from pathlib import Path
pubspec = Path('pubspec.yaml')
pubspec.write_text(pubspec.read_text().replace('path: ../', 'path: ' + json.dumps(sys.argv[1]))
                   + '\naurora:\n  permissions:\n    - Internet\n')
PY
"$flutter_bin" --suppress-analytics pub get
# The fork generates the runner CMake file on its first build.
"$flutter_bin" --suppress-analytics build aurora --release --target-platform aurora-arm64 "$@"
python3 - <<'PY'
from pathlib import Path
cmake = Path('aurora/CMakeLists.txt')
lines = cmake.read_text().splitlines(keepends=True)
if 'This file will be recreated' not in lines[0]:
    raise SystemExit('Expected generated Aurora runner CMake file')
cmake.write_text(''.join(lines[1:]) +
                 '\ntarget_link_libraries(${BINARY_NAME} PRIVATE apptracer_aurora_sdk apptracer_aurora_headers)\n')
PY
cp "$fixture/main.cpp" aurora/main.cpp
cp "$fixture/main.dart" lib/main.dart
"$flutter_bin" --suppress-analytics analyze
"$flutter_bin" --suppress-analytics build aurora --release --no-pub --target-platform aurora-arm64 "$@"
