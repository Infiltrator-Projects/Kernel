#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Isolated QEMU/OVMF boot test; never installs or activates a kernel.
set -euo pipefail
fail() { printf 'InfiltratorOS OVMF: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'InfiltratorOS OVMF: %s\n' "$*" >&2; }

root=$(cd "$(dirname "$0")/../.." && pwd -P)
version=$(tr -d '\r\n' < "$root/VERSION")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid Kernel VERSION: $version"
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] || fail "Invalid Temporary root: $temporary_root"
workspace="$temporary_root/Kernel"
stage="$workspace/Staging/InfiltratorOS-$version"
kernel="$stage/System/Kernel/Images/InfiltratorOS-$version.img"
module=/System/Filesystems/FAT16.so
ovmf=/usr/share/OVMF
boot_version=0.1.39
boot_package="infiltrator-boot_${boot_version}_amd64.deb"
boot_release="https://github.com/Infiltrator-Projects/Boot/releases/download/v${boot_version}"
test_url="https://raw.githubusercontent.com/Infiltrator-Projects/Boot/v${boot_version}/tests/test_so_boot.py"

[[ -s "$kernel" ]] || fail "No staged kernel image: $kernel"
[[ -s "$stage/SHA256SUMS.txt" ]] || fail "Missing staged checksum manifest"
[[ -s "$module" ]] || fail "Missing canonical FAT16.so: $module"
[[ -s "$ovmf/OVMF_CODE_4M.fd" && -s "$ovmf/OVMF_VARS_4M.fd" ]] || fail 'Missing OVMF files'
[[ -s /usr/bin/busybox ]] || fail 'Missing static BusyBox'
file /usr/bin/busybox | grep -Fq 'statically linked' || fail 'BusyBox must be statically linked'
for cmd in wget sha256sum dpkg-deb mkfs.fat mmd mcopy python3 qemu-system-x86_64; do
  command -v "$cmd" >/dev/null || fail "Missing test tool: $cmd"
done

(cd "$stage" && sha256sum --quiet -c SHA256SUMS.txt) || fail 'Staged kernel checksum failure'
log "Verified staged InfiltratorOS Kernel $version checksums"
mkdir -p "$workspace/Tests" || fail "Cannot write $workspace/Tests"
test_root=$(mktemp -d "$workspace/Tests/InfiltratorOS-${version}-OVMF.XXXXXXXX")
log "Test evidence will be preserved at: $test_root"
cd "$test_root"

wget -q -O "$boot_package" "$boot_release/$boot_package" ||
  fail "Cannot download official Boot $boot_version .deb"
wget -q -O SHA256SUMS.txt "$boot_release/SHA256SUMS.txt" ||
  fail "Cannot download Boot $boot_version checksum manifest"
grep -Fq "  $boot_package" SHA256SUMS.txt ||
  fail "Unexpected Boot $boot_version release checksum manifest"
sha256sum -c SHA256SUMS.txt || fail 'Boot package release checksum mismatch'
mkdir -p Boot
dpkg-deb -x "$boot_package" Boot
boot="$test_root/Boot/usr/lib/infiltrator-boot/EFI/BOOT/BOOTX64.EFI"
[[ -s "$boot" ]] || fail 'Official Boot package is missing BOOTX64.EFI'
file "$boot" | grep -Fq 'EFI application' || fail 'BOOTX64.EFI has an invalid file type'
wget -q -O test_so_boot.py "$test_url" ||
  fail 'Cannot fetch Boot 0.1.39 pinned OVMF test harness'

log "Boot EFI: $boot"
log "Kernel: $kernel"
log "Filesystem module: $module"
log 'Launching disposable QEMU/OVMF boot and initramfs handoff test'
if python3 -u "$test_root/test_so_boot.py" \
  --boot "$boot" --module "$module" --kernel "$kernel" \
  --busybox /usr/bin/busybox --ovmf "$ovmf" \
  --output "$test_root/VirtualMachine" 2>&1 | tee "$test_root/Test.log"; then
  grep -Fq 'BOOT-FAT16-SO-LINUX-HANDOFF-PASS' "$test_root/Test.log" ||
    fail 'Missing guest initramfs PASS marker'
  log "PASS: staged InfiltratorOS Kernel $version booted to the VM test initramfs"
else
  log 'VM boot test failed; retaining logs and disposable images'
  if [[ -s "$test_root/VirtualMachine/serial.log" ]]; then
    tail -n 45 "$test_root/VirtualMachine/serial.log" >&2
  fi
  fail "Full test evidence retained in $test_root"
fi
log "VM evidence retained in: $test_root"
log 'No live /System/Kernel, EFI partition, NVRAM or running kernel was changed.'
