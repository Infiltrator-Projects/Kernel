#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Exercise the actual builddeb path writer without compiling a real kernel.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
sh -n "$root/scripts/package/builddeb"
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
abi=7.0.14-infiltrator
mkdir -p "$sandbox/source/scripts/package" "$sandbox/native/include/config" \
  "$sandbox/native/arch/x86/boot" "$sandbox/legacy/include/config" \
  "$sandbox/legacy/arch/x86/boot"
cat > "$sandbox/source/scripts/package/install-extmod-build" <<'STUB'
#!/bin/sh
set -eu
mkdir -p "$1/include"
printf 'compiled header sample\n' > "$1/include/verified.h"
STUB
chmod +x "$sandbox/source/scripts/package/install-extmod-build"
printf 'fake source makefile\n' > "$sandbox/source/Makefile"
cat > "$sandbox/fake-make" <<'MAKE'
#!/bin/sh
set -eu
case " $* " in
  *" modules_install "*)
    path=
    for arg in "$@"; do
      case "$arg" in INSTALL_MOD_PATH=*) path=${arg#INSTALL_MOD_PATH=} ;; esac
    done
    [ -n "$path" ]
    mkdir -p "$path/lib/modules/$KERNELRELEASE/kernel/drivers"
    printf 'compiled module fixture\n' > "$path/lib/modules/$KERNELRELEASE/kernel/drivers/test.ko"
    ;;
  *" image_name "*) printf 'arch/x86/boot/bzImage\n' ;;
  *) echo >&2 "Unexpected fake Kbuild target: $*"; exit 1 ;;
esac
MAKE
chmod +x "$sandbox/fake-make"
for loc in native legacy; do
  printf 'CONFIG_MODULES=y\n' > "$sandbox/$loc/include/config/auto.conf"
  printf 'CONFIG_TEST=y\n' > "$sandbox/$loc/.config"
  printf 'Kernel ABI symbol map\n' > "$sandbox/$loc/System.map"
  printf 'Compiled kernel image\n' > "$sandbox/$loc/arch/x86/boot/bzImage"
done
run_package() {
  local work=$1 pkg=$2 native=$3
  (
    cd "$sandbox/$work"
    INFILTRATOROS_NATIVE_PACKAGE="$native" INFILTRATOROS_KERNEL_VERSION=0.1.0 \
      ARCH=x86 SRCARCH=x86 KERNELRELEASE="$abi" \
      KCONFIG_CONFIG="$sandbox/$work/.config" \
      MAKE="$sandbox/fake-make" srctree="$sandbox/source" \
      sh "$root/scripts/package/builddeb" "$pkg"
  )
}
run_package native infiltratoros-kernel-image-0.1.0 1
runtime="$sandbox/native/debian/infiltratoros-kernel-image-0.1.0"
[[ -s "$runtime/System/Kernel/Images/InfiltratorOS-0.1.0.img" ]]
[[ -s "$runtime/System/Kernel/Images/InfiltratorOS-0.1.0.config" ]]
[[ -s "$runtime/System/Kernel/Images/InfiltratorOS-0.1.0.map" ]]
[[ -s "$runtime/System/Kernel/Modules/InfiltratorOS-0.1.0/kernel/drivers/test.ko" ]]
[[ -d "$runtime/System/Kernel/Filesystems" && -d "$runtime/System/Kernel/Firmware" ]]
[[ ! -e "$runtime/lib" && ! -e "$runtime/usr" && ! -e "$runtime/boot" ]]
[[ ! -e "$runtime/DEBIAN/postinst" && ! -e "$runtime/DEBIAN/preinst" ]]
run_package native infiltratoros-kernel-headers-0.1.0 1
headers="$sandbox/native/debian/infiltratoros-kernel-headers-0.1.0"
[[ -s "$headers/System/Kernel/Headers/InfiltratorOS-0.1.0/include/verified.h" ]]
[[ -L "$headers/System/Kernel/Modules/InfiltratorOS-0.1.0/build" ]]
[[ ! -e "$headers/lib" && ! -e "$headers/usr" && ! -e "$headers/boot" ]]
# Test debug without parsing ELF build IDs; vmlinux and related links must
# still reside entirely inside the native Debug hierarchy.
sed -i '/^CONFIG_MODULES=y$/d' "$sandbox/native/include/config/auto.conf"
printf 'Compiled vmlinux debug symbols\n' > "$sandbox/native/vmlinux"
run_package native infiltratoros-kernel-image-0.1.0-dbg 1
debug="$sandbox/native/debian/infiltratoros-kernel-image-0.1.0-dbg"
[[ -s "$debug/System/Kernel/Debug/InfiltratorOS-0.1.0/lib/modules/$abi/vmlinux" ]]
[[ -L "$debug/System/Kernel/Debug/InfiltratorOS-0.1.0/boot/vmlinux-$abi" ]]
[[ ! -e "$debug/lib" && ! -e "$debug/usr" && ! -e "$debug/boot" ]]

# Unset native mode must retain the original Linux Kbuild payload contract.
run_package legacy "linux-image-$abi" 0
legacy="$sandbox/legacy/debian/linux-image-$abi"
[[ -s "$legacy/boot/vmlinuz-$abi" ]]
[[ -s "$legacy/lib/modules/$abi/kernel/drivers/test.ko" ]]
[[ -x "$legacy/DEBIAN/postinst" ]]
[[ ! -e "$legacy/System" ]]
echo 'PASS: real native builddeb image/headers/debug payload paths, no host hooks, unchanged upstream opt-out'
