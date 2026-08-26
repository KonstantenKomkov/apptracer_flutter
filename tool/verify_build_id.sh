#!/usr/bin/env bash
# Fails the build unless the Dart symbol file matches the libapp.so being shipped.
#
# `--obfuscate --split-debug-info` produces a symbol file that is only usable
# with the exact binary it was generated from; the two are tied together by the
# GNU build id. A mismatch — a stale symbols directory, a rebuild in between, a
# CI step that ran the build twice — is invisible until the day someone needs to
# read a crash, at which point the trace is permanently undecodable.
#
# Run from the example directory after `flutter build apk --obfuscate
# --split-debug-info=build/symbols`.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
apk="${1:-build/app/outputs/flutter-apk/app-release.apk}"
symbols_dir="${2:-build/symbols}"
abi="${ABI:-arm64-v8a}"
symbol_arch="${SYMBOL_ARCH:-android-arm64}"

if [ ! -f "$apk" ]; then
  echo "verify_build_id: no APK at $apk" >&2
  exit 1
fi

symbols_file="$symbols_dir/app.$symbol_arch.symbols"
if [ ! -f "$symbols_file" ]; then
  echo "verify_build_id: no symbol file at $symbols_file" >&2
  echo "  Build with --obfuscate --split-debug-info=$symbols_dir" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

unzip -q -o "$apk" "lib/$abi/libapp.so" -d "$workdir"

apk_build_id="$("$root/tool/elf_build_id.py" "$workdir/lib/$abi/libapp.so")"
symbols_build_id="$("$root/tool/elf_build_id.py" "$symbols_file")"

echo "libapp.so           build id: $apk_build_id"
echo "app.$symbol_arch.symbols build id: $symbols_build_id"

if [ "$apk_build_id" != "$symbols_build_id" ]; then
  echo >&2
  echo "verify_build_id: MISMATCH." >&2
  echo "  The symbol file does not describe the libapp.so in this APK, so the" >&2
  echo "  Dart stack traces of this release can never be decoded. Clean and" >&2
  echo "  rebuild both in one step." >&2
  exit 1
fi

echo "OK: the symbol file describes this build. Archive $symbols_file with the release."
