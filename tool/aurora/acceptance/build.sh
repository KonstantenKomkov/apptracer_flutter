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
mkdir -p "$work/example/lib"
cp "$fixture/main.dart" "$fixture/lifecycle.dart" "$work/example/lib/"
cp "$fixture/main.cpp" "$work/example/aurora/main.cpp"
cp -R "$plugin/example/aurora/icons" "$work/example/aurora/"
cd "$work/example"
python3 - "$plugin" "$repo" <<'PY'
import json
import sys
from pathlib import Path
overrides = Path(sys.argv[1], 'example', 'pubspec_overrides.yaml').read_text()
Path('pubspec_overrides.yaml').write_text(overrides.replace('../../../packages/', sys.argv[2] + '/packages/'))
pubspec = Path('pubspec.yaml')
pubspec.write_text(pubspec.read_text().replace('path: ../', 'path: ' + json.dumps(sys.argv[1]))
                   + '\naurora:\n  permissions:\n    - Internet\n')
PY
"$flutter_bin" --suppress-analytics pub get
"$flutter_bin" --suppress-analytics analyze
"$flutter_bin" --suppress-analytics build aurora --release --no-pub --target-platform aurora-arm64 "$@"
