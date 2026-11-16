#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# InfiltratorOS: signed Common V2 EXT4.so actual mount qualification.
# All media is a disposable regular file. Nothing is installed on the host.
set -euo pipefail
kernel=$(realpath "${1:?compiled InfiltratorOS kernel image}")
provider=$(realpath "${2:?published EXT4.so provider}")
pem=$(realpath "${3:?Kernel trusted signing key and certificate PEM}")
workroot=${4:?VM working directory}
test -s "$kernel" && test -s "$provider" && test -s "$pem"
mkdir -p "$workroot"
work=$(mktemp -d "$workroot/CommonV2-Mount.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/seed/sub" "$work/initrd/bin" "$work/initrd/dev" \
         "$work/initrd/proc" "$work/initrd/mnt" \
         "$work/initrd/System/Filesystems"
printf 'COMMON_V2_EXT4_REAL_FILE_READ\n' > "$work/seed/hello.txt"
printf 'NESTED_ENTRY\n' > "$work/seed/sub/nested.txt"
ln -s /hello.txt "$work/seed/alias.txt"
truncate -s 64M "$work/root.img"
features=has_journal,ext_attr,resize_inode,dir_index,filetype,extent,64bit,flex_bg
features+=,sparse_super,large_file,huge_file,dir_nlink,extra_isize,metadata_csum
mkfs.ext4 -q -F -b 4096 -O "none,$features" -d "$work/seed" \
    -L EXT4ROOT "$work/root.img"
before=$(sha256sum "$work/root.img" | cut -d' ' -f1)

cp "$provider" "$work/initrd/System/Filesystems/EXT4.so"
openssl cms -sign -binary -noattr -nosmimecap -md sha256 \
    -in "$work/initrd/System/Filesystems/EXT4.so" \
    -signer "$pem" -inkey "$pem" -outform DER \
    -out "$work/initrd/System/Filesystems/EXT4.so.p7s"
test -s "$work/initrd/System/Filesystems/EXT4.so.p7s"

cp "$(command -v busybox)" "$work/initrd/bin/busybox"
ln -s busybox "$work/initrd/bin/sh"
sudo mknod -m 600 "$work/initrd/dev/console" c 5 1
sudo mknod -m 666 "$work/initrd/dev/null" c 1 3
cat > "$work/initrd/init" <<'GUEST'
#!/bin/sh
set -eu
b=/bin/busybox
exec </dev/console >/dev/console 2>&1
$b mount -t devtmpfs devtmpfs /dev
$b mount -t proc proc /proc
if $b grep -qw ext4 /proc/filesystems; then
  echo COMMON_V2_NATIVE_FORMAT_FALLBACK_DETECTED
  $b poweroff -f
fi
if $b grep -q 'ifs_trial=unsigned' /proc/cmdline; then
  if $b mount -t infiltratr-v2 -o ro,format=ext4 /dev/vda /mnt; then
    echo COMMON_V2_INVALID_SIGNATURE_ACCEPTED
  else
    echo COMMON_V2_INVALID_SIGNATURE_REJECTED
  fi
else
  $b mount -t infiltratr-v2 -o ro,format=ext4 /dev/vda /mnt
  $b grep -Fqx COMMON_V2_EXT4_REAL_FILE_READ /mnt/hello.txt
  $b grep -Fqx NESTED_ENTRY /mnt/sub/nested.txt
  $b ls /mnt | $b grep -Fqx hello.txt
  $b cat /proc/mounts | $b grep -F ' /mnt infiltratr-v2 '
  echo COMMON_V2_SIGNED_MOUNT_READ_PASS
fi
$b sync
$b poweroff -f
GUEST
chmod 755 "$work/initrd/init"

pack() {
  local archive=$1
  (cd "$work/initrd" && find . -print0 | cpio --null -o -H newc --quiet | gzip -n) > "$archive"
}
boot() {
  local archive=$1 log=$2 mode=$3 success=$4
  timeout 140 qemu-system-x86_64 \
    -machine q35,accel=tcg -cpu max -m 768 \
    -display none -monitor none -serial "file:$log" \
    -no-reboot -nic none \
    -drive "if=none,format=raw,id=volume,file=$work/root.img,readonly=on" \
    -device virtio-blk-pci,drive=volume \
    -kernel "$kernel" -initrd "$archive" \
    -append "console=ttyS0 rdinit=/init panic=1 ifs_trial=$mode" || {
        tail -n 90 "$log" >&2
        return 1
    }
  if ! grep -Fxq "$success" "$log"; then
    tail -n 90 "$log" >&2
    return 1
  fi
  printf '%s\n' "$success"
}

pack "$work/signed.cpio.gz"
boot "$work/signed.cpio.gz" "$work/signed.log" signed COMMON_V2_SIGNED_MOUNT_READ_PASS

# The same exact byte-for-byte certified carrier becomes invalid on mutation.
printf '\n' >> "$work/initrd/System/Filesystems/EXT4.so"
pack "$work/mutated.cpio.gz"
boot "$work/mutated.cpio.gz" "$work/mutated.log" unsigned COMMON_V2_INVALID_SIGNATURE_REJECTED
after=$(sha256sum "$work/root.img" | cut -d' ' -f1)
test "$before" = "$after"
echo COMMON_V2_HOST_MEDIA_UNCHANGED
