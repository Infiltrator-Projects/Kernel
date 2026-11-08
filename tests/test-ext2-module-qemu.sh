#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Cloud-only, disposable EXT2 runtime qualification for InfiltratorOS Kernel.
# No real partitions, host boot files, EFI NVRAM, or loaded host modules touched.
set -euo pipefail
fail() { printf 'EXT2-QUALIFICATION-FAIL: %s\n' "$*" >&2; exit 1; }
log() { printf 'EXT2-QUALIFICATION: %s\n' "$*" >&2; }
[[ $# == 4 ]] || fail 'Usage: test-ext2-module-qemu.sh KERNEL_IMAGE EXT2_KO WORKSPACE EXPECTED_KERNELRELEASE'
kernel=$1
module=$2
out=$3
release=$4
[[ -s "$kernel" && -s "$module" ]] || fail 'Missing compiled kernel or module'
[[ "$out" == /* && "$out" != / ]] || fail 'Workspace must be absolute'
[[ $(modinfo -F vermagic "$module" | awk '{print $1}') == "$release" ]] ||
  fail 'EXT2 .ko vermagic does not match native kernel'
for executable in qemu-system-x86_64 mkfs.ext2 e2fsck debugfs cpio gzip timeout sha256sum busybox; do
  command -v "$executable" >/dev/null || fail "Missing dependency: $executable"
done
[[ $(file "$(command -v busybox)") == *'statically linked'* ]] ||
  fail 'busybox-static is mandatory for independent guest userland'
mkdir -p "$out"
image="$out/ext2-qualify.img"
root="$out/initramfs"
mkdir -p "$root/bin" "$root/dev" "$root/proc" "$root/sys" "$root/mnt/ext2"
truncate -s 96M "$image"
fixture="$out/fixture"
mkdir -p "$fixture"
printf 'Cloud-verified EXT2 source fixture\n' > "$fixture/source.txt"
expected_hash=$(sha256sum "$fixture/source.txt" | cut -d' ' -f1)
mkfs.ext2 -F -q -d "$fixture" "$image"
install -m 755 "$(command -v busybox)" "$root/bin/busybox"
ln -s busybox "$root/bin/sh"
install -m 644 "$module" "$root/ext2.ko"
# Linux opens /dev/console before executing init. A device node in the
# archive is legitimate on GitHub-hosted CI and never touches host /dev.
sudo mknod "$root/dev/console" c 5 1
sudo mknod "$root/dev/null" c 1 3
cat > "$root/init" <<'INIT'
#!/bin/sh
export PATH=/bin
fail() {
  echo "EXT2_GUEST_FAIL:$1"
  /bin/busybox poweroff -f
  exit 1
}
/bin/busybox mount -t devtmpfs devtmpfs /dev || fail devtmpfs
/bin/busybox mount -t proc proc /proc || fail proc
/bin/busybox insmod /ext2.ko || fail insmod
/bin/busybox grep -Eq '^[[:space:]]*ext2$' /proc/filesystems || fail registration
/bin/busybox mount -t ext2 -o rw /dev/vda /mnt/ext2 || fail mount
if [ -f /mnt/ext2/renamed.txt ]; then
  /bin/busybox grep -qx 'EXT2 durable content and rename' /mnt/ext2/renamed.txt || fail persisted_data
  /bin/busybox grep -qx 'Cloud-verified EXT2 source fixture' /mnt/ext2/source.txt || fail persisted_fixture
  /bin/busybox grep -qx 'EXT2 nested directory content' /mnt/ext2/tree/nested.txt || fail persisted_directory
  echo EXT2_SECOND_BOOT_PERSISTENCE_PASS
else
  /bin/busybox grep -qx 'Cloud-verified EXT2 source fixture' /mnt/ext2/source.txt || fail fixture
  echo 'EXT2 durable content and rename' > /mnt/ext2/new.txt || fail write
  /bin/busybox mv /mnt/ext2/new.txt /mnt/ext2/renamed.txt || fail rename
  /bin/busybox mkdir /mnt/ext2/tree || fail mkdir
  echo 'EXT2 nested directory content' > /mnt/ext2/tree/nested.txt || fail directory_write
  /bin/busybox sync
  /bin/busybox umount /mnt/ext2 || fail unmount1
  /bin/busybox mount -t ext2 /dev/vda /mnt/ext2 || fail remount
  /bin/busybox grep -qx 'EXT2 durable content and rename' /mnt/ext2/renamed.txt || fail remount_data
  /bin/busybox grep -qx 'EXT2 nested directory content' /mnt/ext2/tree/nested.txt || fail remount_directory
  echo EXT2_FIRST_BOOT_MOUNT_WRITE_RENAME_REMOUNT_PASS
fi
/bin/busybox sync
/bin/busybox umount /mnt/ext2 || fail unmount_final
/bin/busybox poweroff -f
INIT
chmod +x "$root/init"
# The guest script is a separate shell program; parse it before QEMU.
sh -n "$root/init" || fail 'Invalid generated guest /init shell syntax'
(cd "$root" && find . -print0 | cpio --null -o -H newc --quiet | gzip -9) > "$out/initramfs.cpio.gz"
run_vm() {
  local number=$1 serial="$out/guest-$1.serial.log"
  log "Running isolated QEMU guest $number (EXT2 image persists across boots)"
  # Virtio block is built in, not loaded from the userspace module tree.
  timeout --signal=TERM --kill-after=10s 110s qemu-system-x86_64 \
    -nodefaults -machine q35 -m 1024 -smp 2 -display none \
    -no-reboot -monitor none -serial "file:$serial" \
    -kernel "$kernel" -initrd "$out/initramfs.cpio.gz" \
    -append 'console=ttyS0,115200 rdinit=/init panic=1' \
    -device virtio-blk-pci,drive=ext2disk \
    -drive "if=none,id=ext2disk,format=raw,file=$image,cache=writeback" \
    > "$out/qemu-$number.log" 2>&1 ||
    fail "QEMU guest $number did not exit cleanly; examine $serial"
  if grep -Fq 'EXT2_GUEST_FAIL:' "$serial"; then
    fail "Guest $number reported a module/filesystem failure"
  fi
}
run_vm 1
grep -Fq 'EXT2_FIRST_BOOT_MOUNT_WRITE_RENAME_REMOUNT_PASS' "$out/guest-1.serial.log" ||
  fail 'First guest failed to prove mount, write, rename and remount'
log 'Read-only offline ext2 fsck after first boot'
e2fsck -fn "$image" > "$out/e2fsck-first.log" 2>&1 ||
  fail 'First offline fsck found errors'
run_vm 2
grep -Fq 'EXT2_SECOND_BOOT_PERSISTENCE_PASS' "$out/guest-2.serial.log" ||
  fail 'Second independent boot failed persistent-data checks'
e2fsck -fn "$image" > "$out/e2fsck-second.log" 2>&1 ||
  fail 'Second offline fsck found errors'
debugfs -R 'cat /renamed.txt' "$image" 2> "$out/debugfs.log" |
  grep -qx 'EXT2 durable content and rename' ||
  fail 'Offline independent reader did not see renamed data'
[[ $expected_hash == "$(debugfs -R 'cat /source.txt' "$image" 2>/dev/null | sha256sum | cut -d' ' -f1)" ]] ||
  fail 'Original fixture digest changed'
log 'EXT2_KERNEL_0.1.0_TWO_BOOT_RW_RENAME_DURABILITY_PASS'
