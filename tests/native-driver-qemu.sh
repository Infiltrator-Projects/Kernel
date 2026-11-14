#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Exercise kernel-initiated driver autoload from the native hierarchy with no
# /lib/modules tree, using only a disposable initramfs and virtual machine.
set -euo pipefail
kernel=$(realpath "${1:?compiled kernel image required}")
stage=$(realpath "${2:?staged native kernel required}")
workspace=$(realpath -m "${3:?temporary workspace required}")
os_loader_source=$(realpath "${4:?verified InfiltratorOS device loader source required}")
udev_rule=$(realpath "${5:?verified InfiltratorOS device rule required}")
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
mkdir -p "$root"/{bin,dev,proc,sys,run,etc/udev/rules.d,System/Kernel/Modules,System/Kernel/Runtime,System/Kernel/Firmware,System/Commands/InfiltratorOS}
printf 'InfiltratorOS native firmware qualification\n' > "$root/System/Kernel/Firmware/native-qualification.bin"
cp "$(command -v busybox)" "$root/bin/busybox"
ln -s busybox "$root/bin/sh"
cp -a "$module_root" "$root/System/Kernel/Modules/"
cp -a "$(dirname "$helper")" "$root/System/Kernel/Runtime/"
cp "$udev_rule" "$root/etc/udev/rules.d/81-infiltratoros-drivers.rules"
cc -std=c11 -O2 -Wall -Wextra -Werror "$os_loader_source" \
    -o "$root/System/Commands/InfiltratorOS/load-native-driver"
ip=$(command -v ip)
udevadm=$(command -v udevadm)
udevd=/usr/lib/systemd/systemd-udevd
[[ -x $udevd && -x $udevadm ]]
cp -L --parents "$ip" "$root"
cp -L --parents "$udevd" "$udevadm" "$root"
for executable in "$ip" "$udevd" "$udevadm" "$helper" "$root/System/Commands/InfiltratorOS/load-native-driver"; do
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
# A real udev event runs the exact conversion package's rule and loader. The
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
UDEVD_COMMAND --daemon
UDEVADM_COMMAND control --ping
# Coldplug all devices so the real udev rules discover the NIC, USB HID
# transport/tablet and Intel HDA controller by their respective aliases.
UDEVADM_COMMAND trigger --action=add --type=devices
UDEVADM_COMMAND settle --timeout=30
test -d /sys/module/e1000e
test -L "$device/driver"
test -d /sys/module/usbhid
test -d /sys/module/hid_generic
test -d /sys/module/snd_hda_intel
audio=
for alias_file in /sys/bus/pci/devices/*/modalias; do
    alias=$($b cat "$alias_file")
    case "$alias" in
        pci:v00008086d00002668*) audio=${alias_file%/modalias}; break ;;
    esac
done
test -n "$audio"
test -L "$audio/driver"
# Check that a USB input device actually registered; merely loading the
# module would not establish binding. Physical laptop operation is separate.
usb_input=0
for input in /sys/class/input/input*; do
    test -f "$input/id/bustype" || continue
    if test "$($b cat "$input/id/bustype")" = 0003; then usb_input=1; fi
done
test "$usb_input" = 1
test -d /sys/class/sound
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
sed -i "s|UDEVD_COMMAND|$udevd|g; s|UDEVADM_COMMAND|$udevadm|g" "$root/init"
chmod 0755 "$root/init"
(cd "$root" && find . -print0 | cpio --null -o -H newc --quiet --owner=0:0 | gzip -1) > "$work/initramfs.gz"
if ! timeout 90 qemu-system-x86_64 -machine q35,accel=tcg -cpu max -m 512 \
    -display none -monitor none -serial "file:$work/serial.log" -no-reboot \
    -netdev user,id=net0,restrict=on -device e1000e,netdev=net0 \
    -device qemu-xhci,id=xhci -device usb-tablet,bus=xhci.0 \
    -device intel-hda -device hda-duplex \
    -kernel "$kernel" -initrd "$work/initramfs.gz" \
    -append 'console=ttyS0 rdinit=/init panic=1' ||
    ! awk '{ sub(/\r$/, ""); if ($0 == "NATIVE_DRIVER_AUTOLOAD_PASS") found=1 }
           END { exit !found }' "$work/serial.log"; then
    tail -n 100 "$work/serial.log" >&2
    exit 1
fi
echo NATIVE_DRIVER_AUTOLOAD_PASS
