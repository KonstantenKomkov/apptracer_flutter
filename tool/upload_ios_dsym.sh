#!/usr/bin/env bash
# Uploads iOS dSYM bundles to Tracer. Fails closed.
#
# The vendor documents this as an Xcode Run Script phase guarded by
# `ACTION == install && CONFIGURATION == Release`, which means it only ever
# fires during an archive. That is inconvenient to verify and easy to have
# silently not run, so this does the same upload from the command line, the
# same way tool/upload_web_sourcemaps.sh does for web.
#
# "Fails closed" means: no token, no dSYM, an empty archive, a failed request
# or a response that is not explicitly a success exits non-zero. A release that
# ships without symbols looks fine until the first crash, and by then the build
# is gone.
#
# The plugin token is read from the environment and never appears in argv, so it
# does not leak into process listings or CI logs.
#
# Usage:
#   TRACER_PLUGIN_TOKEN=... tool/upload_ios_dsym.sh <dsym-dir> <version-name> [version-code]
set -euo pipefail

dsym_dir="${1:?usage: TRACER_PLUGIN_TOKEN=... upload_ios_dsym.sh <dsym-dir> <version-name> [version-code]}"
version_name="${2:?version name is required}"
version_code="${3:-1}"
endpoint="${TRACER_SYMBOL_ENDPOINT:-https://plugin-api.apptracer.ru/api/symbol/upload}"

if [ -z "${TRACER_PLUGIN_TOKEN:-}" ]; then
  echo "upload_ios_dsym: TRACER_PLUGIN_TOKEN is not set." >&2
  exit 1
fi

if [ ! -d "$dsym_dir" ]; then
  echo "upload_ios_dsym: $dsym_dir does not exist." >&2
  echo "  A release device build writes it next to the .app:" >&2
  echo "  flutter build ios --release" >&2
  exit 1
fi

count="$(find "$dsym_dir" -maxdepth 1 -name '*.dSYM' | wc -l | tr -d ' ')"
if [ "$count" -eq 0 ]; then
  echo "upload_ios_dsym: no .dSYM bundles in $dsym_dir." >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
archive="$workdir/dsym.zip"

# -y keeps symlinks as symlinks; a dSYM bundle contains them, and following
# them would double the archive and confuse the server about what it received.
(cd "$dsym_dir" && zip -qry "$archive" ./*.dSYM)

echo "upload_ios_dsym: $count bundle(s), $(du -h "$archive" | cut -f1), version $version_name ($version_code)"

response="$(curl --silent --show-error --location --http1.1 \
  --form "versionName=$version_name" \
  --form "versionCode=$version_code" \
  --form "file=@$archive" \
  "$endpoint?symbolToken=$TRACER_PLUGIN_TOKEN")" || {
  echo "upload_ios_dsym: the request failed." >&2
  exit 1
}

echo "upload_ios_dsym: server said: $response"

case "$response" in
  *'"success":true'*|*'"success": true'*) ;;
  *)
    echo "upload_ios_dsym: the server did not confirm success." >&2
    exit 1
    ;;
esac

echo "upload_ios_dsym: uploaded."
