#!/usr/bin/env bash
# Run the load-only probe against the pinned SDK on an Aurora guest over SSH.
set -euo pipefail

if (( $# < 2 )); then
  echo "Usage: $0 /path/to/guest-probe [ssh options] user@emulator" >&2
  exit 2
fi
probe=$1
shift
repo=$(cd "$(dirname "$0")/../.." && pwd)
sdk=${APPTRACER_AURORA_SDK_ROOT:-"$repo/build/aurora-sdk/0.1.15"}
python3 "$repo/tool/prepare_aurora_sdk.py" --verify-only --destination "$sdk" >/dev/null

ssh_cmd=(ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$@")
arch=$("${ssh_cmd[@]}" '. /etc/os-release && test "$ID" = auroraos && uname -m')
case "$arch" in
  aarch64|x86_64) ;;
  *) echo "Unknown Aurora guest ABI: $arch" >&2; exit 1 ;;
esac

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp "$probe" "$stage/probe"
chmod 755 "$stage/probe"
cp "$sdk/aurora/lib/$arch/libtracernative.so" "$stage/"
COPYFILE_DISABLE=1 tar -cf - -C "$stage" probe libtracernative.so |
  "${ssh_cmd[@]}" '
    set -eu
    stage=$(mktemp -d /tmp/apptracer-probe.XXXXXX)
    trap '\''rm -rf "$stage"'\'' EXIT
    cd "$stage"
    tar xf -
    . /etc/os-release
    echo "$PRETTY_NAME ($(uname -m))"
    getconf GNU_LIBC_VERSION
    rpm -q libopenssl
    rpm -q crash-dumper || true
    cat /proc/sys/kernel/core_pattern
    sha256sum libtracernative.so
    ./probe "$stage/libtracernative.so"
  '
