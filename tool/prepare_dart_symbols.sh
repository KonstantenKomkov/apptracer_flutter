#!/usr/bin/env bash
# Stages Dart AOT symbols so the Tracer Gradle plugin will upload them.
#
# Why this works
# --------------
# `--obfuscate --split-debug-info=DIR` strips Dart symbol names out of
# libapp.so and writes them to DIR/app.<platform>-<arch>.symbols, an ELF debug
# companion carrying the *same GNU build id* as the stripped libapp.so.
#
# The Tracer Gradle plugin's CollectSymbolsTask walks every file under
# `additionalLibrariesPath`, runs the bundled breakpad `dump_syms` over it, and
# uploads the resulting .sym. It filters on "is a file", not on extension, so
# the Dart symbol file is a candidate like any other. Measured on a real build:
#
#   dump_syms app.android-arm64.symbols -> 7545 FUNC entries with Dart names
#   dump_syms libapp.so (stripped)      -> 0 FUNC entries
#   both -> MODULE Linux arm64 <same id>
#
# The one thing that does not match is the MODULE *name*, which dump_syms takes
# from the file name. Copying the symbol file to `libapp.so` inside the staging
# directory makes the name match too, so the uploaded symbols line up with the
# library they describe on both name and build id.
#
# The plugin walks additionalLibrariesPath *after* the merged native libs and
# keys every entry by (file name, build id), so the staged file replaces the
# stripped libapp.so instead of joining it. Leave forceUploadNativeSymbols off:
# the staged file parses as FULL, so it is never dropped as unusable, and
# nothing else claims its (name, build id) at the `nativesymbol/exists` check.
# The vendor confirmed on 2026-08-27 that the backend matches on the build id
# from .note.gnu.build-id, the way minidump-stackwalk does.
#
# Caveats worth reading before you turn this on
# ---------------------------------------------
# * MEASURED 2026-08-27: the upload works and buys nothing. Tracer's crash
#   reporter records libapp.so with a zero build id and a base shifted by the
#   executable segment's offset, so these symbols are never matched to a frame.
#   Kept because the defect is the vendor's and may be fixed; until then use
#   `flutter symbolize`. See docs/symbolication.md, finding 2.
# * The symbol file embeds absolute source paths from the build machine and the
#   full set of Dart symbol names. Uploading it sends both to Tracer.
#
# Usage:
#   tool/prepare_dart_symbols.sh <split-debug-info-dir> [staging-dir]
#   DART_SPLIT_DEBUG_INFO=<staging-dir> flutter build apk --release ...
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
symbols_dir="${1:?usage: prepare_dart_symbols.sh <split-debug-info-dir> [staging-dir]}"
staging_dir="${2:-$symbols_dir/tracer-upload}"

if [ ! -d "$symbols_dir" ]; then
  echo "prepare_dart_symbols: $symbols_dir does not exist." >&2
  echo "  Build with --obfuscate --split-debug-info=$symbols_dir first." >&2
  exit 1
fi

rm -rf "$staging_dir"
mkdir -p "$staging_dir"

staged=0
for symbols in "$symbols_dir"/app.*.symbols; do
  [ -e "$symbols" ] || continue

  build_id="$("$root/tool/elf_build_id.py" "$symbols")"
  # The staging directory is flat, so a build covering several architectures
  # would collide on the name `libapp.so`. Keep them apart by build id and let
  # the caller point additionalLibrariesPath at one of them per variant.
  target_dir="$staging_dir/$build_id"
  mkdir -p "$target_dir"
  cp "$symbols" "$target_dir/libapp.so"
  echo "staged $(basename "$symbols") as $target_dir/libapp.so (build id $build_id)"
  staged=$((staged + 1))
done

if [ "$staged" -eq 0 ]; then
  echo "prepare_dart_symbols: no app.*.symbols found in $symbols_dir" >&2
  exit 1
fi

if [ "$staged" -gt 1 ]; then
  echo
  echo "Note: $staged architectures staged in separate directories. Point"
  echo "additionalLibrariesPath at $staging_dir to cover them all — the walk is"
  echo "recursive and entries are keyed by name and build id — or at a single"
  echo "subdirectory to upload one variant."
fi
