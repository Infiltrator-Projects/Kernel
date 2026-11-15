#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cc -std=c11 -O2 -Wall -Wextra -Werror \
  "$root/scripts/infiltrator/prune-external-filesystems.c" -o "$work/profile"
config="$work/kernel configuration"
printf 'CONFIG_XFS_FS=y\nCONFIG_BTRFS_FS=m\n# CONFIG_UFS_FS is not set\nCONFIG_UFS_FS=m\nCONFIG_EXT4_FS=y\nCONFIG_FAT_FS=m\n' > "$config"
"$work/profile" apply "$config"
"$work/profile" check "$config"
grep -Fxq 'CONFIG_EXT4_FS=y' "$config"
grep -Fxq 'CONFIG_FAT_FS=m' "$config"
grep -Fxq '# CONFIG_XFS_FS is not set' "$config"
[[ $(grep -Fc '# CONFIG_UFS_FS is not set' "$config") == 1 ]]
cp "$config" "$work/once"
"$work/profile" apply "$config"
cmp "$config" "$work/once"
printf 'CONFIG_XFS_FS=m\n' >> "$config"
if "$work/profile" check "$config"; then exit 1; fi
printf 'CONFIG_XFS_FS=invalid\n' > "$config"
cp "$config" "$work/bad"
if "$work/profile" apply "$config"; then exit 1; fi
cmp "$config" "$work/bad"
printf 'CONFIG_EXT4_FS=y\r\nCONFIG_TMPFS=y' > "$config"
"$work/profile" apply "$config"
printf 'CONFIG_EXT4_FS=y\r\nCONFIG_TMPFS=y\n' > "$work/prefix"
head -c "$(wc -c < "$work/prefix")" "$config" > "$work/actual"
cmp "$work/prefix" "$work/actual"
echo 'NATIVE_FILESYSTEM_PROFILE_PASS'
