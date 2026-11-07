#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Verify the real Kbuild Debian generator's identity, without compiling a kernel.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
testdir=$(mktemp -d)
trap 'rm -rf -- "$testdir"' EXIT
mkdir -p "$testdir/include/config"
cat > "$testdir/include/config/auto.conf" <<'CONFIG'
CONFIG_MODULES=y
CONFIG_DEBUG_INFO=y
CONFIG_64BIT=y
CONFIG
printf 'CONFIG_MODULES=y\n' > "$testdir/.config"
(
  cd "$testdir"
  env ARCH=x86 SRCARCH=x86 UTS_MACHINE=x86_64 KERNELRELEASE=0.1.0-infiltrator \
    srctree="$root" KCONFIG_CONFIG="$testdir/.config" \
    INFILTRATOROS_NATIVE_PACKAGE=1 INFILTRATOROS_KERNEL_VERSION=0.1.0 \
    sh "$root/scripts/package/mkdebian"
)
control="$testdir/debian/control"
changelog="$testdir/debian/changelog"
grep -Fxq 'Source: infiltratoros-kernel' "$control"
grep -Fxq 'Package: infiltratoros-kernel-image-0.1.0' "$control"
grep -Fxq 'Package: infiltratoros-kernel-image-0.1.0-dbg' "$control"
grep -Fxq 'Package: infiltratoros-kernel-headers-0.1.0' "$control"
grep -Fxq 'XB-X-InfiltratorOS-Kernel-Version: 0.1.0' "$control"
grep -Fxq 'XB-X-InfiltratorOS-Module-ABI: 0.1.0-infiltrator' "$control"
[[ $(grep -Fc 'XB-X-InfiltratorOS-Module-ABI: 0.1.0-infiltrator' "$control") -eq 3 ]]

# A source debian/control check alone was insufficient: dpkg-gencontrol
# silently removed the earlier X- fields before the compiled .deb was built.
# Exercise the REAL Debian binary-control generation and read back the .deb.
binary_package=infiltratoros-kernel-image-0.1.0
mkdir -p "$testdir/debian/$binary_package/DEBIAN"
(
  cd "$testdir"
  dpkg-gencontrol "-p$binary_package" "-Pdebian/$binary_package" -O \
    > "$testdir/generated-binary-control"
)
cp "$testdir/generated-binary-control" "$testdir/debian/$binary_package/DEBIAN/control"
dpkg-deb --build "$testdir/debian/$binary_package" "$testdir/native-identity.deb" >/dev/null
[[ $(dpkg-deb -f "$testdir/native-identity.deb" X-InfiltratorOS-Kernel-Version) == 0.1.0 ]]
[[ $(dpkg-deb -f "$testdir/native-identity.deb" X-InfiltratorOS-Module-ABI) == 0.1.0-infiltrator ]]
! grep -Eq '^Package: linux-(image|headers|libc-dev)' "$control"
head -n1 "$changelog" | grep -Fq 'infiltratoros-kernel (0.1.0-3)'
grep -Fq 'infiltratoros-kernel-image-%' "$root/scripts/package/debian/rules"
grep -Fq 'infiltratoros-kernel-headers-%' "$root/scripts/package/debian/rules"
grep -Fq 'infiltratoros-kernel-image-*' "$root/scripts/package/builddeb"
grep -Fq 'infiltratoros-kernel-headers-*' "$root/scripts/package/builddeb"
grep -Fq 'version=${KERNELRELEASE}' "$root/scripts/package/builddeb"
# The real native Debian generator must produce payloads for the native
# /System/Kernel namespace, not traditional /boot, /lib/modules or /usr/src.
sh -n "$root/scripts/package/builddeb"
grep -Fq 'if [ "$native_mode" -eq 1 ]; then' "$root/scripts/package/builddeb"
grep -Fq 'native_root="${pdir}/System/Kernel"' "$root/scripts/package/builddeb"
grep -Fq 'System/Kernel/Headers/InfiltratorOS-' "$root/scripts/package/builddeb"
grep -Fq 'System/Kernel/Debug/InfiltratorOS-' "$root/scripts/package/builddeb"
grep -Fq 'packageversion=${product_version}-3' "$root/scripts/package/mkdebian"


# Default mode must still generate upstream Linux names (for compatibility
# with direct Kbuild and non-InfiltratorOS users of the imported source).
mkdir -p "$testdir/legacy/include/config"
cp "$testdir/include/config/auto.conf" "$testdir/legacy/include/config/auto.conf"
(
  cd "$testdir/legacy"
  env -u INFILTRATOROS_NATIVE_PACKAGE -u INFILTRATOROS_KERNEL_VERSION \
    ARCH=x86 SRCARCH=x86 UTS_MACHINE=x86_64 KERNELRELEASE=7.0.14-infiltrator \
    srctree="$root" KCONFIG_CONFIG="$testdir/.config" \
    sh "$root/scripts/package/mkdebian"
)
grep -Fxq 'Package: linux-image-7.0.14-infiltrator' "$testdir/legacy/debian/control"
grep -Fxq 'Package: linux-headers-7.0.14-infiltrator' "$testdir/legacy/debian/control"
! grep -Fq 'Package: infiltratoros-kernel-' "$testdir/legacy/debian/control"
echo 'PASS: native Debian image/headers/debug identity and verified dpkg-gencontrol binary ABI fields'
