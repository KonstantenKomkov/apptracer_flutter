#!/usr/bin/env bash
# Uploads Flutter web source maps to Tracer. Fails closed.
#
# "Fails closed" means: if the archive is empty, the token is missing, the
# request fails, or the server does not explicitly answer {"success":true},
# this script exits non-zero. A release that silently ships without usable
# source maps looks fine until the first crash, and by then the build is gone.
#
# Two Tracer-specific rules that are easy to get wrong:
#
#   * Tracer matches source maps by file PATH, not by Debug ID as Sentry does.
#     The paths inside the archive must match the paths in the stack frames.
#   * `versionName` must equal the `release` the SDK reports. Tracer strips
#     everything up to and including the last `@`, so `my_app@1.2.3` is stored
#     as `1.2.3` — pass the same thing here.
#
# The plugin token is read from the environment and never appears in argv, so it
# does not leak into process listings or CI logs.
#
# Usage:
#   TRACER_PLUGIN_TOKEN=... tool/upload_web_sourcemaps.sh <version> [build-dir]
set -euo pipefail

version="${1:?usage: TRACER_PLUGIN_TOKEN=... upload_web_sourcemaps.sh <version> [build-dir]}"
build_dir="${2:-build/web}"
endpoint="${TRACER_SOURCEMAP_ENDPOINT:-https://plugin-api.apptracer.ru/api/sourcemap/upload}"

if [ -z "${TRACER_PLUGIN_TOKEN:-}" ]; then
  echo "upload_web_sourcemaps: TRACER_PLUGIN_TOKEN is not set." >&2
  exit 1
fi

if [ ! -d "$build_dir" ]; then
  echo "upload_web_sourcemaps: $build_dir does not exist." >&2
  echo "  Build with: flutter build web --release --source-maps" >&2
  exit 1
fi

map_count="$(find "$build_dir" -name '*.map' | wc -l | tr -d ' ')"
if [ "$map_count" -eq 0 ]; then
  echo "upload_web_sourcemaps: no .map files under $build_dir." >&2
  echo "  The build was made without --source-maps, so nothing can be" >&2
  echo "  symbolicated. Refusing to report success." >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
archive="$workdir/assets.zip"

# Zip from inside build_dir so the archive paths match the paths the browser
# reports in stack frames.
(cd "$build_dir" && zip -q -r "$archive" . -i '*.js' '*.map')

echo "uploading $map_count source maps for version $version"

response_file="$workdir/response.json"
http_status="$(
  curl --silent --show-error --fail-with-body \
    --max-time 300 \
    --output "$response_file" \
    --write-out '%{http_code}' \
    -F "sourcemapToken=$TRACER_PLUGIN_TOKEN" \
    -F "versionName=$version" \
    -F "file=@$archive" \
    "$endpoint"
)" || {
  echo "upload_web_sourcemaps: request failed (HTTP $http_status)." >&2
  # The response body can echo the request; never print it, it may contain the
  # token.
  exit 1
}

if ! grep -q '"success":[[:space:]]*true' "$response_file"; then
  echo "upload_web_sourcemaps: server did not confirm success (HTTP $http_status)." >&2
  exit 1
fi

echo "OK: source maps accepted for version $version."
echo "Note: they apply only to errors received after this upload, so deploy now."
