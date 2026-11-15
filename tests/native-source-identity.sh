#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
. "$root/scripts/infiltrator/source-identity.sh"
mkdir -p "$work/docs/upstream"
printf '%s\n' 'linux-hwe-7.0=7.0.0-42.42~24.04.1' > "$work/docs/upstream/source-id"
unset -v pkg ver
native_source_identity "$work"
[[ "$pkg" == linux-hwe-7.0 && "$ver" == '7.0.0-42.42~24.04.1' ]]
# The actual builder writes both values under set -u after compilation.
printf 'source_package=%s\nsource_version=%s\n' "$pkg" "$ver" > "$work/provenance"
grep -Fxq 'source_package=linux-hwe-7.0' "$work/provenance"
grep -Fxq 'source_version=7.0.0-42.42~24.04.1' "$work/provenance"
rm "$work/docs/upstream/source-id"
unset -v pkg ver
native_source_identity "$work"
[[ "$pkg" == pinned-git-source && "$ver" == unknown ]]
printf '%s\n' 'invalid-identity' > "$work/docs/upstream/source-id"
if native_source_identity "$work"; then
  echo 'Invalid source identity was accepted' >&2; exit 1
fi
grep -Fq 'native_source_identity "$source_dir"' "$root/scripts/build-native.sh"
echo 'NATIVE_SOURCE_IDENTITY_PASS'
