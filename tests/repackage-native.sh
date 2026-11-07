#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Prove native Debian packages can be generated from compiled files with NO
# kernel compilation, installation, host changes or original mutations.
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/infiltrator/repackage-native.sh
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
version=$(tr -d '\r\n' < VERSION)
abi=7.0.14-infiltrator
packages="$sandbox/Original"
stage="$sandbox/Stage"
dest="$sandbox/Temporary/InfiltratorOS/Kernel/Packages/NativeLayout"
mkdir -p "$packages" "$stage/System/Kernel/Images" \
  "$stage/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers" \
  "$stage/System/Kernel/Filesystems" "$stage/System/Kernel/Firmware"
printf 'Compiled image with exact ABI\n' > "$stage/System/Kernel/Images/InfiltratorOS-$version.img"
printf 'CONFIG_TEST=y\n' > "$stage/System/Kernel/Images/InfiltratorOS-$version.config"
printf 'Test symbol table\n' > "$stage/System/Kernel/Images/InfiltratorOS-$version.map"
printf 'Compiled module payload\n' > "$stage/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/example.ko"
printf 'product_version=%s\nkernel_release=%s\n' "$version" "$abi" > "$stage/STAGING-STATUS.txt"
(cd "$stage" && find System -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS.txt)
cp "$stage/SHA256SUMS.txt" "$sandbox/original-stage-manifest"
mkdir -p "$sandbox/pkg/DEBIAN"
for pkg in "infiltratoros-kernel-image-$version" \
           "infiltratoros-kernel-headers-$version" \
           "infiltratoros-kernel-image-$version-dbg"; do
  mkdir -p "$sandbox/pkg/DEBIAN"
  cat > "$sandbox/pkg/DEBIAN/control" <<EOF
Package: $pkg
Version: $version-1
Architecture: amd64
Maintainer: InfiltratorOS Test <test@example.invalid>
Description: Fake compiled baseline package for path testing
EOF
  case "$pkg" in
    "infiltratoros-kernel-image-$version")
      mkdir -p "$sandbox/pkg/boot" "$sandbox/pkg/lib/modules/$abi/kernel/drivers"
      printf 'old linux image\n' > "$sandbox/pkg/boot/vmlinuz-$abi"
      printf 'old linux module\n' > "$sandbox/pkg/lib/modules/$abi/kernel/drivers/example.ko" ;;
    "infiltratoros-kernel-headers-$version")
      mkdir -p "$sandbox/pkg/usr/src/linux-headers-$abi/include"
      printf 'compiled headers\n' > "$sandbox/pkg/usr/src/linux-headers-$abi/include/test.h" ;;
    "infiltratoros-kernel-image-$version-dbg")
      mkdir -p "$sandbox/pkg/usr/lib/debug/lib/modules/$abi/kernel/drivers" \
        "$sandbox/pkg/usr/lib/debug/.build-id/ab"
      printf 'debug symbols\n' > "$sandbox/pkg/usr/lib/debug/lib/modules/$abi/vmlinux"
      printf 'module debug\n' > "$sandbox/pkg/usr/lib/debug/lib/modules/$abi/kernel/drivers/example.ko"
      ln -s "../../lib/modules/$abi/kernel/drivers/example.ko" \
        "$sandbox/pkg/usr/lib/debug/.build-id/ab/test.debug" ;;
  esac
  dpkg-deb --build "$sandbox/pkg" "$packages/${pkg}_${version}-1_amd64.deb" >/dev/null
  # A separate test-data directory for each package avoids inherited files
  # contaminating the expected Debian payload in this synthetic test.
  rm -rf "$sandbox/pkg"
done
original_image_hash=$(sha256sum "$stage/System/Kernel/Images/InfiltratorOS-$version.img" | cut -d' ' -f1)
bash scripts/infiltrator/repackage-native.sh \
  --packages "$packages" --stage "$stage" --output "$dest"
final="$dest/InfiltratorOS-$version"
[[ -s "$final/SHA256SUMS.txt" && -s "$final/NATIVE-PACKAGING-STATUS.txt" ]]
(cd "$final" && sha256sum --quiet -c SHA256SUMS.txt)
grep -Fxq 'Recompiled=no' "$final/NATIVE-PACKAGING-STATUS.txt"
for pkg in "infiltratoros-kernel-image-$version" \
           "infiltratoros-kernel-headers-$version" \
           "infiltratoros-kernel-image-$version-dbg"; do
  file="$final/${pkg}_${version}-2_amd64.deb"
  [[ -s "$file" ]]
  [[ $(dpkg-deb -f "$file" Package) == "$pkg" ]]
  [[ $(dpkg-deb -f "$file" Version) == "$version-2" ]]
  [[ $(dpkg-deb -f "$file" X-InfiltratorOS-Module-ABI) == "$abi" ]]
  dpkg-deb -x "$file" "$sandbox/Unpacked/$pkg"
  [[ ! -e "$sandbox/Unpacked/$pkg/boot" ]]
  [[ ! -e "$sandbox/Unpacked/$pkg/usr" ]]
  [[ ! -e "$sandbox/Unpacked/$pkg/lib" ]]
  [[ -d "$sandbox/Unpacked/$pkg/System/Kernel" ]]
  dpkg-deb -e "$file" "$sandbox/UnpackedControl/$pkg"
  [[ ! -e "$sandbox/UnpackedControl/$pkg/postinst" &&
     ! -e "$sandbox/UnpackedControl/$pkg/preinst" ]]
done
image="$sandbox/Unpacked/infiltratoros-kernel-image-$version"
headers="$sandbox/Unpacked/infiltratoros-kernel-headers-$version"
debug="$sandbox/Unpacked/infiltratoros-kernel-image-$version-dbg"
[[ -s "$image/System/Kernel/Images/InfiltratorOS-$version.img" ]]
[[ -s "$image/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/example.ko" ]]
[[ -s "$headers/System/Kernel/Headers/InfiltratorOS-$version/include/test.h" ]]
[[ -L "$headers/System/Kernel/Modules/InfiltratorOS-$version/build" ]]
[[ -s "$debug/System/Kernel/Debug/InfiltratorOS-$version/lib/modules/$abi/vmlinux" ]]
[[ -L "$debug/System/Kernel/Debug/InfiltratorOS-$version/.build-id/ab/test.debug" ]]
[[ $(sha256sum "$stage/System/Kernel/Images/InfiltratorOS-$version.img" | cut -d' ' -f1) == "$original_image_hash" ]]
cmp "$stage/SHA256SUMS.txt" "$sandbox/original-stage-manifest"
if bash scripts/infiltrator/repackage-native.sh --packages "$packages" \
  --stage "$stage" --output "$dest" > "$sandbox/second-attempt.log" 2>&1; then
  echo 'ERROR: Native repacker overwrote already verified output' >&2; exit 1
fi
grep -Fq 'refusing to overwrite' "$sandbox/second-attempt.log"
echo 'PASS: actual native Debian paths for all three packages, immutable baseline, no compilation or host install'
