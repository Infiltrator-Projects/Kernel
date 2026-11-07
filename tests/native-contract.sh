#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validate native filesystem staging without compiling a kernel.
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/infiltrator/stage-native.sh
bash -n scripts/infiltrator/package-run.sh
for binary in dpkg-deb rsync; do command -v "$binary" >/dev/null; done
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
release=7.0.14-infiltrator
mkdir -p "$sandbox/pkg/DEBIAN" "$sandbox/pkg/boot" "$sandbox/pkg/lib/modules/$release/kernel/drivers" \
  "$sandbox/packages" "$sandbox/obj/include/config"
cat > "$sandbox/pkg/DEBIAN/control" <<EOF_CONTROL
Package: linux-image-$release
Version: 7.0.14-1
Architecture: amd64
Maintainer: InfiltratorOS test harness <noreply@example.invalid>
Description: Fake test image for native staging contract
EOF_CONTROL
printf 'test image\n' > "$sandbox/pkg/boot/vmlinuz-$release"
printf 'test module\n' > "$sandbox/pkg/lib/modules/$release/kernel/drivers/test.ko"
printf '%s\n' "$release" > "$sandbox/obj/include/config/kernel.release"
printf 'CONFIG_TEST=y\n' > "$sandbox/obj/.config"
dpkg-deb --build "$sandbox/pkg" "$sandbox/packages/fake.deb" >/dev/null
bash scripts/infiltrator/stage-native.sh --packages "$sandbox/packages" --objects "$sandbox/obj" --output "$sandbox/native"
[[ -s "$sandbox/native/System/Kernel/Images/InfiltratorOS-$release.img" ]]
[[ -s "$sandbox/native/System/Kernel/Modules/$release/kernel/drivers/test.ko" ]]
[[ -d "$sandbox/native/System/Kernel/Filesystems" ]]
[[ -d "$sandbox/native/System/Kernel/Firmware" ]]
[[ ! -e "$sandbox/native/boot" && ! -e "$sandbox/native/lib" ]]
( cd "$sandbox/native" && sha256sum -c SHA256SUMS.txt >/dev/null )
bash scripts/infiltrator/stage-native.sh --packages "$sandbox/packages" --objects "$sandbox/obj" --output "$sandbox/native"
( cd "$sandbox/native" && sha256sum -c SHA256SUMS.txt >/dev/null )
echo 'PASS: native image/modules layout, checksum integrity and repeated local staging'
