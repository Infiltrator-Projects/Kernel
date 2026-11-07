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
[[ -s "$sandbox/native/System/Kernel/Images/InfiltratorOS-0.1.0.img" ]]
[[ -s "$sandbox/native/System/Kernel/Modules/InfiltratorOS-0.1.0/kernel/drivers/test.ko" ]]
[[ ! -e "$sandbox/native/System/Kernel/Modules/$release" ]]
[[ -d "$sandbox/native/System/Kernel/Filesystems" ]]
[[ -d "$sandbox/native/System/Kernel/Firmware" ]]
[[ ! -e "$sandbox/native/boot" && ! -e "$sandbox/native/lib" ]]
( cd "$sandbox/native" && sha256sum -c SHA256SUMS.txt >/dev/null )
# A second staging pass must not silently overwrite the original output.
if bash scripts/infiltrator/stage-native.sh --packages "$sandbox/packages" --objects "$sandbox/obj" --output "$sandbox/native" > "$sandbox/refused.log" 2>&1; then
  echo 'FAIL: stage overwrote the original without explicit replacement' >&2
  exit 1
fi
grep -Fq 'Output already exists' "$sandbox/refused.log"
bash scripts/infiltrator/stage-native.sh --packages "$sandbox/packages" --objects "$sandbox/obj" --output "$sandbox/native" --replace
( cd "$sandbox/native" && sha256sum -c SHA256SUMS.txt >/dev/null )

# If both a preserved Linux-named baseline and a new native image are present,
# stage the native package matching this component version and exact module ABI.
mkdir -p "$sandbox/newpkg/DEBIAN" "$sandbox/newpkg/boot" "$sandbox/newpkg/lib/modules/$release/kernel/drivers"
cat > "$sandbox/newpkg/DEBIAN/control" <<EOF_NATIVE
Package: infiltratoros-kernel-image-0.1.0
Version: 0.1.0-1
Architecture: amd64
Maintainer: InfiltratorOS test harness <noreply@example.invalid>
X-InfiltratorOS-Kernel-Version: 0.1.0
X-InfiltratorOS-Module-ABI: $release
Description: Native kernel packaging contract test
EOF_NATIVE
printf 'native image\n' > "$sandbox/newpkg/boot/vmlinuz-$release"
printf 'native module\n' > "$sandbox/newpkg/lib/modules/$release/kernel/drivers/test.ko"
dpkg-deb --build "$sandbox/newpkg" "$sandbox/packages/native.deb" >/dev/null
bash scripts/infiltrator/stage-native.sh --packages "$sandbox/packages" --objects "$sandbox/obj" --output "$sandbox/native-0.1.0"
grep -Fxq 'native image' "$sandbox/native-0.1.0/System/Kernel/Images/InfiltratorOS-0.1.0.img"
grep -Fxq 'product_version=0.1.0' "$sandbox/native-0.1.0/STAGING-STATUS.txt"
grep -Fxq "transitional_module_abi=$release" "$sandbox/native-0.1.0/STAGING-STATUS.txt"
grep -Fxq 'staging_location=Temporary' "$sandbox/native-0.1.0/STAGING-STATUS.txt"
[[ -s "$sandbox/native-0.1.0/System/Kernel/Modules/InfiltratorOS-0.1.0/kernel/drivers/test.ko" ]]
[[ ! -e "$sandbox/native-0.1.0/System/Kernel/Modules/$release" ]]
( cd "$sandbox/native-0.1.0" && sha256sum -c SHA256SUMS.txt >/dev/null )
echo 'PASS: native product version/ABI identity, legacy package fallback, checksums and preservation'
