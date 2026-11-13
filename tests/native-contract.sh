#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validate native filesystem staging without compiling a kernel.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(<VERSION)
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
[[ -s "$sandbox/native/System/Kernel/Images/InfiltratorOS-$version.img" ]]
[[ -s "$sandbox/native/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/test.ko" ]]
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
Package: infiltratoros-kernel-image-$version
Version: $version-1
Architecture: amd64
Maintainer: InfiltratorOS test harness <noreply@example.invalid>
X-InfiltratorOS-Kernel-Version: $version
X-InfiltratorOS-Module-ABI: $release
Description: Native kernel packaging contract test
EOF_NATIVE
printf 'native image\n' > "$sandbox/newpkg/boot/vmlinuz-$release"
printf 'native module\n' > "$sandbox/newpkg/lib/modules/$release/kernel/drivers/test.ko"
dpkg-deb --build "$sandbox/newpkg" "$sandbox/packages/native.deb" >/dev/null
bash scripts/infiltrator/stage-native.sh --packages "$sandbox/packages" --objects "$sandbox/obj" --output "$sandbox/native-$version"
grep -Fxq 'native image' "$sandbox/native-$version/System/Kernel/Images/InfiltratorOS-$version.img"
grep -Fxq "product_version=$version" "$sandbox/native-$version/STAGING-STATUS.txt"
grep -Fxq "transitional_module_abi=$release" "$sandbox/native-$version/STAGING-STATUS.txt"
grep -Fxq 'staging_location=Temporary' "$sandbox/native-$version/STAGING-STATUS.txt"
[[ -s "$sandbox/native-$version/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/test.ko" ]]
[[ ! -e "$sandbox/native-$version/System/Kernel/Modules/$release" ]]
( cd "$sandbox/native-$version" && sha256sum -c SHA256SUMS.txt >/dev/null )

# Default production staging must use /Temporary/InfiltratorOS, not dist,
# and must retain the correct /System/Kernel skeleton without installing it.
native_temp="$sandbox/Temporary/InfiltratorOS"
INFILTRATOROS_TEMP_ROOT="$native_temp" bash scripts/infiltrator/stage-native.sh \
  --packages "$sandbox/packages" --objects "$sandbox/obj"
native_stage="$native_temp/Kernel/Staging/InfiltratorOS-$version"
[[ -s "$native_stage/System/Kernel/Images/InfiltratorOS-$version.img" ]]
[[ -s "$native_stage/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/test.ko" ]]
[[ ! -e "$native_stage/System/Kernel/Modules/$release" ]]
[[ ! -e "$sandbox/Temporary/InfiltratorOS/dist" ]]
( cd "$native_stage" && sha256sum -c SHA256SUMS.txt >/dev/null )

# Regression: the first production InfiltratorOS .deb packages were
# already built, but their source-only X-... fields were omitted by
# dpkg-gencontrol. Accept that known historical binary only after examining
# the exact compiled boot image and loadable module payload.
mkdir -p "$sandbox/missing-abi/DEBIAN" "$sandbox/missing-abi/boot" \
  "$sandbox/missing-abi/lib/modules/$release/kernel/drivers" \
  "$sandbox/missing-abi-packages"
cat > "$sandbox/missing-abi/DEBIAN/control" <<EOF_MISSING
Package: infiltratoros-kernel-image-$version
Version: $version-1
Architecture: amd64
Maintainer: InfiltratorOS test harness <noreply@example.invalid>
Description: Historically compiled image lacking optional binary ABI field
EOF_MISSING
printf 'native image without field\n' > "$sandbox/missing-abi/boot/vmlinuz-$release"
printf 'native module without field\n' > "$sandbox/missing-abi/lib/modules/$release/kernel/drivers/test.ko"
dpkg-deb --build "$sandbox/missing-abi" "$sandbox/missing-abi-packages/no-abi-field.deb" >/dev/null
bash scripts/infiltrator/stage-native.sh --packages "$sandbox/missing-abi-packages" \
  --objects "$sandbox/obj" --output "$sandbox/native-noabi"
grep -Fxq 'native image without field' "$sandbox/native-noabi/System/Kernel/Images/InfiltratorOS-$version.img"
[[ -s "$sandbox/native-noabi/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/test.ko" ]]
( cd "$sandbox/native-noabi" && sha256sum -c SHA256SUMS.txt >/dev/null )

# A package with no metadata must NOT pass merely because its Debian package
# name looks correct. Requiring the actual image and matching module path
# catches incorrect payloads before the staging result becomes visible.
mkdir -p "$sandbox/wrong-abi-packages"
mv "$sandbox/missing-abi/boot/vmlinuz-$release" "$sandbox/missing-abi/boot/vmlinuz-unrelated"
dpkg-deb --build "$sandbox/missing-abi" "$sandbox/wrong-abi-packages/wrong-abi.deb" >/dev/null
if bash scripts/infiltrator/stage-native.sh --packages "$sandbox/wrong-abi-packages" \
  --objects "$sandbox/obj" --output "$sandbox/native-wrong-abi" \
  >"$sandbox/wrong-abi.log" 2>&1; then
  echo 'FAIL: package with missing ABI metadata and incompatible image was staged' >&2
  exit 1
fi
grep -Fq 'Compiled boot image not found' "$sandbox/wrong-abi.log"
[[ ! -e "$sandbox/native-wrong-abi" ]]

# New native-layout -2 .deb packages must also be accepted as staging inputs
# without depending on /boot or /lib/modules in the extracted package.
mkdir -p "$sandbox/native2pkg/DEBIAN" \
  "$sandbox/native2pkg/System/Kernel/Images" \
  "$sandbox/native2pkg/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers" \
  "$sandbox/native2packages"
cat > "$sandbox/native2pkg/DEBIAN/control" <<EOF_NATIVE2
Package: infiltratoros-kernel-image-$version
Version: $version-2
Architecture: amd64
Maintainer: InfiltratorOS test harness <noreply@example.invalid>
X-InfiltratorOS-Kernel-Version: $version
X-InfiltratorOS-Module-ABI: $release
Description: Proper native installation paths fixture
EOF_NATIVE2
printf 'correct native image\n' > "$sandbox/native2pkg/System/Kernel/Images/InfiltratorOS-$version.img"
printf 'correct native config\n' > "$sandbox/native2pkg/System/Kernel/Images/InfiltratorOS-$version.config"
printf 'correct native .ko\n' > "$sandbox/native2pkg/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/native2.ko"
dpkg-deb --build "$sandbox/native2pkg" "$sandbox/native2packages/real-native-path.deb" >/dev/null
bash scripts/infiltrator/stage-native.sh --packages "$sandbox/native2packages" \
  --objects "$sandbox/obj" --output "$sandbox/re-staged-native2"
grep -Fxq 'correct native image' "$sandbox/re-staged-native2/System/Kernel/Images/InfiltratorOS-$version.img"
grep -Fxq 'correct native config' "$sandbox/re-staged-native2/System/Kernel/Images/InfiltratorOS-$version.config"
grep -Fxq 'correct native .ko' "$sandbox/re-staged-native2/System/Kernel/Modules/InfiltratorOS-$version/kernel/drivers/native2.ko"
[[ ! -e "$sandbox/re-staged-native2/boot" && ! -e "$sandbox/re-staged-native2/lib" ]]
(cd "$sandbox/re-staged-native2" && sha256sum --quiet -c SHA256SUMS.txt)
echo 'PASS: native Temporary staging, old Linux-path and new native-path package inputs, ABI validation and preservation'
