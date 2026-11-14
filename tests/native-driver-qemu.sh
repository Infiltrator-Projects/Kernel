#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Exercise kernel-initiated driver autoload from the native hierarchy with no
# /lib/modules tree, using only a disposable initramfs and virtual machine.
set -euo pipefail
kernel=$(realpath "${1:?compiled kernel image required}")
stage=$(realpath "${2:?staged native kernel required}")
workspace=$(realpath -m "${3:?temporary workspace required}")
os_loader_source=$(realpath "${4:?verified InfiltratorOS device loader source required}")
version=$(<"$(dirname "$0")/../VERSION")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
native="InfiltratorOS-$version"
module_root="$stage/System/Kernel/Modules/$native"
helper="$stage/System/Kernel/Runtime/$native/modprobe"
[[ -x $helper && -s $module_root/modules.dep.bin && -s $module_root/modules.alias.bin ]]
dummy=$(find "$module_root/kernel" -type f -name 'dummy.ko*' -print -quit)
[[ -n $dummy ]]
modinfo -F alias "$dummy" | grep -Fxq 'rtnl-link-dummy'
mkdir -p "$workspace"
work=$(mktemp -d "$workspace/Kernel-Drivers.XXXXXXXX")
root="$work/initramfs"
mkdir -p "$root"/{bin,dev,proc,sys,System/Kernel/Modules,System/Kernel/Runtime,System/Kernel/Firmware,System/Commands/InfiltratorOS}
printf 'InfiltratorOS native firmware qualification\n' > "$root/System/Kernel/Firmware/native-qualification.bin"
cp "$(command -v busybox)" "$root/bin/busybox"
ln -s busybox "$root/bin/sh"
cp -a "$module_root" "$root/System/Kernel/Modules/"
cp -a "$(dirname "$helper")" "$root/System/Kernel/Runtime/"
cc -std=c11 -O2 -Wall -Wextra -Werror "$os_loader_source" \
    -o "$root/System/Commands/InfiltratorOS/load-native-driver"
ip=$(command -v ip)
cp -L --parents "$ip" "$root"
for executable in "$ip" "$helper" "$root/System/Commands/InfiltratorOS/load-native-driver"; do
    while IFS= read -r library; do
        cp -L --parents "$library" "$root"
    done < <(ldd "$executable" | awk '$2 == "=>" && $3 ~ /^\// {print $3} $1 ~ /^\// {print $1}')
done
cat > "$root/init" <<'GUEST'
#!/bin/sh
b=/bin/busybox
$b mount -t devtmpfs devtmpfs /dev
exec </dev/ttyS0 >/dev/ttyS0 2>&1
trap '/bin/busybox poweroff -f' EXIT
set -eu
$b mount -t proc proc /proc
$b mount -t sysfs sysfs /sys
version=$($b uname -r)
helper="/System/Kernel/Runtime/InfiltratorOS-$version/modprobe"
test ! -e "/lib/modules/$version"
test "$($b cat /proc/sys/kernel/modprobe)" = "$helper"
test ! -d /sys/module/dummy
# rtnetlink requests rtnl-link-dummy from the configured kernel helper.
IP_COMMAND link add native0 type dummy
test -d /sys/module/dummy
IP_COMMAND link show native0
# A udev modalias event enters the real conversion package's loader. The
# virtual PCI adapter exercises the same alias discovery as hardware hotplug.
test ! -d /sys/module/e1000e
device=
for alias_file in /sys/bus/pci/devices/*/modalias; do
    alias=$($b cat "$alias_file")
    case "$alias" in
        pci:v00008086d000010D3*) device=${alias_file%/modalias}; break ;;
    esac
done
test -n "$device"
/System/Commands/InfiltratorOS/load-native-driver "$alias"
test -d /sys/module/e1000e
test -L "$device/driver"
# Exercise the real kernel firmware loader with a modular test device. The
# guest has no /lib/firmware: a successful request proves the compiled
# native search path finds the exact bytes under /System/Kernel/Firmware.
"$helper" -- test_firmware
test -e /dev/test_firmware
printf '%s' native-qualification.bin > /sys/devices/virtual/misc/test_firmware/trigger_request
$b cmp /System/Kernel/Firmware/native-qualification.bin /dev/test_firmware
if "$helper" -q -- infiltratoros_missing_driver_000000; then
    echo NATIVE_MISSING_DRIVER_FALSE_SUCCESS
    exit 1
fi
echo NATIVE_DRIVER_AUTOLOAD_PASS
GUEST
# ip may reside under /sbin or /usr/sbin on the build host.
sed -i "s|IP_COMMAND|$ip|g" "$root/init"
chmod 0755 "$root/init"
(cd "$root" && find . -print0 | cpio --null -o -H newc --quiet --owner=0:0 | gzip -1) > "$work/initramfs.gz"
if ! timeout 90 qemu-system-x86_64 -machine q35,accel=tcg -cpu max -m 512 \
    -display none -monitor none -serial "file:$work/serial.log" -no-reboot \
    -netdev user,id=net0,restrict=on -device e1000e,netdev=net0 \
    -kernel "$kernel" -initrd "$work/initramfs.gz" \
    -append 'console=ttyS0 rdinit=/init panic=1' ||
    ! awk '{ sub(/\r$/, ""); if ($0 == "NATIVE_DRIVER_AUTOLOAD_PASS") found=1 }
           END { exit !found }' "$work/serial.log"; then
    tail -n 100 "$work/serial.log" >&2
    exit 1
fi
echo NATIVE_DRIVER_AUTOLOAD_PASS
