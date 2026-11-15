#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cc -std=c11 -O2 -Wall -Wextra -Werror \
  "$root/scripts/infiltrator/prune-external-filesystems.c" -o "$work/profile"
config="$work/kernel configuration"
printf 'CONFIG_XFS_FS=y\nCONFIG_BTRFS_FS=m\n# CONFIG_UFS_FS is not set\nCONFIG_NTFS3_FS=m\nCONFIG_HFS_FS=m\nCONFIG_HFSPLUS_FS=m\nCONFIG_EXFAT_FS=m\nCONFIG_EXT4_FS=y\nCONFIG_FAT_FS=m\n' > "$config"
cp "$config" "$work/original"
"$work/profile" apply "$config"
"$work/profile" check "$config"
cmp "$config" "$work/original"
# Repeating the compatibility gate must never remove working drivers.
"$work/profile" apply "$config"
cmp "$config" "$work/original"
printf 'CONFIG_XFS_FS=invalid\n' >> "$config"
cp "$config" "$work/invalid"
if "$work/profile" check "$config"; then exit 1; fi
if "$work/profile" apply "$config"; then exit 1; fi
cmp "$config" "$work/invalid"
echo 'NATIVE_FILESYSTEM_COMPATIBILITY_PASS'
