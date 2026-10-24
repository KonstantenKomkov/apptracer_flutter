#!/usr/bin/env bash
# Ubuntu x86_64 release + exact native/Dart symbol artifacts. No credentials.
set -euo pipefail
cd "$(dirname "$0")/../packages/apptracer_flutter_desktop/example"
test "$(uname -s)" = Linux
test "$(uname -m)" = x86_64
export SENTRY_NATIVE_BACKEND=native
# WSL can inherit a Windows JAVA_HOME, which FindJNI cannot use.
if [[ ! -f "${JAVA_HOME:-}/include/jni.h" ]]; then
  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
  export JAVA_HOME
fi
flutter pub get
flutter build linux --release --obfuscate --split-debug-info=build/symbols/dart
bundle=build/linux/x64/release/bundle
test -x "$bundle/lib/sentry-crash"
python3 ../../../tool/prepare_linux_symbol_tools.py --output build/symbol-tools
python3 ../../../tool/prepare_linux_runtime_symbols.py --bundle "$bundle" \
  --dump-syms build/symbol-tools/dump_syms
# The example includes names/source paths for automatic Dart source display.
# Opt out when retaining obfuscation is more important than client symbolication.
if [[ "${TRACER_BUNDLE_DART_SYMBOLS:-1}" == 1 ]]; then
  python3 ../../../tool/prepare_linux_dart_runtime_symbols.py --bundle "$bundle" \
    --symbols build/symbols/dart/app.linux-x64.symbols \
    --dump-syms build/symbol-tools/dump_syms
fi
mkdir -p build/symbols/native
objcopy --only-keep-debug "$bundle/apptracer_desktop_example" build/symbols/native/runner.debug
cp "$bundle/apptracer_desktop_example" build/symbols/native/runner.elf
cp "$bundle/lib/libapp.so" build/symbols/native/libapp.so
cp "$bundle/lib/libsentry.so" build/symbols/native/libsentry.so
python3 ../../../tool/elf_build_id.py "$bundle/apptracer_desktop_example" > build/symbols/native/runner.build-id
python3 ../../../tool/elf_build_id.py "$bundle/lib/libapp.so" > build/symbols/native/dart.build-id
python3 ../../../tool/elf_build_id.py build/symbols/dart/app.linux-x64.symbols > build/symbols/native/dart-symbols.build-id
cmp build/symbols/native/dart.build-id build/symbols/native/dart-symbols.build-id
sha256sum "$bundle/apptracer_desktop_example" "$bundle/lib/libapp.so" \
  "$bundle/lib/libsentry.so" "$bundle/lib/sentry-crash" \
  build/symbols/dart/app.linux-x64.symbols > build/symbols/SHA256SUMS
ldd "$bundle/apptracer_desktop_example" > build/symbols/runner.ldd.txt
ldd "$bundle/lib/libsentry.so" > build/symbols/sentry.ldd.txt
if grep -q 'not found' build/symbols/*.ldd.txt; then
  echo 'Missing runtime libraries' >&2
  exit 1
fi
