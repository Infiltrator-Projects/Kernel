#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Synthetic native install: simulate an entire new machine without sudo.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
version=$(tr -d '\r\n' < "$root/VERSION")
abi=0.1.0-infiltrator
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
packages="$sandbox/Packages"
temp_root="$sandbox/Temporary/InfiltratorOS"
install_root="$sandbox/IsolatedRoot"
mkdir -p "$packages" "$temp_root/Kernel" "$install_root/System/Kernel/Filesystems" \
  "$sandbox/Package/DEBIAN"
# Confirm an existing unrelated filesystem module remains unchanged.
printf 'Independent filesystem provider\n' > "$install_root/System/Kernel/Filesystems/FAT16.ko"
before=$(sha256sum "$install_root/System/Kernel/Filesystems/FAT16.ko" | cut -d' ' -f1)
for name in "infiltratoros-kernel-image-$version" \
  "infiltratoros-kernel-headers-$version" \
  "infiltratoros-kernel-image-$version-dbg"; do
  p="$sandbox/Package"
  cat > "$p/DEBIAN/control" <<EOF
Package: $name
Version: $version-3
Architecture: amd64
Maintainer: InfiltratorOS Test <test@example.invalid>
X-InfiltratorOS-Module-ABI: $abi
Description: Native only fixture
EOF
  case "$name" in
    "infiltratoros-kernel-image-$version")
      mkdir -p "$p/System/Kernel/Images" \
        "$p/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers"
      printf 'compiled native image\n' > "$p/System/Kernel/Images/InfiltratorOS-$version.img"
      printf 'compiled native .config\n' > "$p/System/Kernel/Images/InfiltratorOS-$version.config"
      printf 'compiled native symbols\n' > "$p/System/Kernel/Images/InfiltratorOS-$version.map"
      printf 'compiled native ko\n' > "$p/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/test.ko" ;;
    "infiltratoros-kernel-headers-$version")
      mkdir -p "$p/System/Kernel/Headers/InfiltratorOS-$version/include"
      printf 'compiled header\n' > "$p/System/Kernel/Headers/InfiltratorOS-$version/include/test.h" ;;
    "infiltratoros-kernel-image-$version-dbg")
      mkdir -p "$p/System/Kernel/Debug/InfiltratorOS-$version/lib/modules/$abi"
      printf 'compiled vmlinux\n' > "$p/System/Kernel/Debug/InfiltratorOS-$version/lib/modules/$abi/vmlinux" ;;
  esac
  dpkg-deb --build "$p" "$packages/${name}_${version}-2_amd64.deb" >/dev/null
  rm -rf "$p/System"
done
(cd "$packages" && sha256sum ./*.deb > "SHA256SUMS-InfiltratorOS-Kernel-$version.txt")
INFILTRATOROS_TEMP_ROOT="$temp_root" \
  bash "$root/scripts/infiltrator/install-native.sh" \
  --packages "$packages" --install-root "$install_root"
[[ -s "$install_root/System/Kernel/Images/InfiltratorOS-$version.img" ]]
[[ -s "$install_root/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/test.ko" ]]
[[ -s "$install_root/System/Kernel/Headers/InfiltratorOS-$version/include/test.h" ]]
[[ -s "$install_root/System/Kernel/Debug/InfiltratorOS-$version/lib/modules/$abi/vmlinux" ]]
[[ ! -e "$install_root/boot" && ! -e "$install_root/lib" && ! -e "$install_root/usr" ]]
[[ $(sha256sum "$install_root/System/Kernel/Filesystems/FAT16.ko" | cut -d' ' -f1) == "$before" ]]
if INFILTRATOROS_TEMP_ROOT="$temp_root" \
  bash "$root/scripts/infiltrator/install-native.sh" \
  --packages "$packages" --install-root "$install_root" \
  > "$sandbox/reinstall.log" 2>&1; then
  echo 'ERROR: Native installer overwrote the existing kernel' >&2
  exit 1
fi
grep -Fq 'Refusing to overwrite existing native kernel installation' "$sandbox/reinstall.log"
# Previously published 0.1.0 packages may already occupy these paths.
# Repair MUST require explicit approval, preserve their bytes and leave
# independent filesystem providers unchanged.
printf 'old wrong-ABI kernel image\n' > "$install_root/System/Kernel/Images/InfiltratorOS-$version.img"
INFILTRATOROS_TEMP_ROOT="$temp_root" \
  bash "$root/scripts/infiltrator/install-native.sh" \
  --packages "$packages" --install-root "$install_root" --replace-existing
[[ $(cat "$install_root/System/Kernel/Images/InfiltratorOS-$version.img") == 'compiled native image' ]]
backup_file=$(find "$temp_root/Kernel/Backups" -type f -name "InfiltratorOS-$version.img" -print -quit)
[[ -n "$backup_file" && $(cat "$backup_file") == 'old wrong-ABI kernel image' ]]
[[ $(sha256sum "$install_root/System/Kernel/Filesystems/FAT16.ko" | cut -d' ' -f1) == "$before" ]]
echo 'PASS: native install, explicit same-version repair backup, independent filesystem preservation'
