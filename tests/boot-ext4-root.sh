#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Exercise built-in GPT, NVMe and EXT4 with a real root and no initramfs.
set -euo pipefail
kernel=$(realpath "${1:?compiled x86 kernel image required}")
workspace=${2:?trial workspace required}
version=$(<"$(dirname "$0")/../VERSION")
test -s "$kernel"
mkdir -p "$workspace"
work=$(mktemp -d "$workspace/Kernel-EXT4.XXXXXXXX")
root="$work/root"
mkdir -p "$root"/{bin,dev,proc,sbin}
cp "$(command -v busybox)" "$root/bin/"
ln -s busybox "$root/bin/sh"
cat > "$root/sbin/init" <<'GUEST'
#!/bin/sh
set -eu
b=/bin/busybox
exec </dev/ttyS0 >/dev/ttyS0 2>&1
trap '/bin/busybox poweroff -f' EXIT
$b mount -t proc proc /proc
test "$($b uname -r)" = "QUALIFIED_KERNEL_VERSION"
# Linux's direct root mount may report /dev/root as its source.
$b awk '$2 == "/" && $3 == "ext4" && $4 ~ /^rw(,|$)/ { found=1 }
        END { exit !found }' /proc/mounts
if $b grep -qw ext4_reboot /proc/cmdline; then
    $b grep -Fx 'native kernel wrote EXT4' /ext4-proof
    echo NATIVE_EXT4_REBOOT_PASS
else
    printf '%s\n' 'native kernel wrote EXT4' > /ext4-proof
    echo NATIVE_EXT4_WRITE_PASS
fi
$b sync
$b mount -o remount,ro /
GUEST
sed -i "s/QUALIFIED_KERNEL_VERSION/$version/" "$root/sbin/init"
chmod 0755 "$root/sbin/init"
truncate -s 80M "$work/disk.img"
sgdisk -n 1:2048:+8M -t 1:ef00 -n 2:18432:+64M -t 2:8300 "$work/disk.img"
truncate -s 64M "$work/root.img"
mkfs.ext4 -q -F -b 4096 -d "$root" "$work/root.img"
dd if="$work/root.img" of="$work/disk.img" bs=1M seek=9 conv=notrunc status=none

boot() {
    local log=$1 marker=$2 options=${3:-}
    if ! timeout 90 qemu-system-x86_64 -machine q35,accel=tcg -cpu max -m 512 \
        -display none -monitor none -serial "file:$log" -no-reboot -nic none \
        -drive "if=none,format=raw,id=root,file=$work/disk.img" \
        -device nvme,drive=root,serial=ext4-test \
        -kernel "$kernel" \
        -append "console=ttyS0 root=/dev/nvme0n1p2 rootfstype=ext4 rootwait rw panic=1 $options" ||
        ! grep -q "^$marker" "$log"; then
        tail -n 70 "$log" >&2
        return 1
    fi
    printf '%s\n' "$marker"
}

boot "$work/serial.log" NATIVE_EXT4_WRITE_PASS
boot "$work/serial-reboot.log" NATIVE_EXT4_REBOOT_PASS ext4_reboot
