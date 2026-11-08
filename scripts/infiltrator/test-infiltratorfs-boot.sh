#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Image-only integration: Boot -> InfiltratorFS 0.19 -> native Kernel -> VFS.
# Never alters real disks, installed bootloaders, NVRAM or host kernel modules.
set -euo pipefail
fail() { printf 'InfiltratorOS three-way trial: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'InfiltratorOS three-way trial: %s\n' "$*" >&2; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
version=$(tr -d '\r\n' < "$root/VERSION")
[[ "$version" == 0.1.0 ]] || fail 'Only InfiltratorOS Kernel 0.1.0 is qualified'
source= objects= stage= workspace= jobs=2 install_deps=0
while (( $# )); do
  case "$1" in
    --install-deps) install_deps=1 ;;
    --source|--objects|--stage|--workspace|--jobs)
      key=$1; shift; (( $# )) || fail "Missing value for $key"
      case "$key" in
        --source) source=$1 ;; --objects) objects=$1 ;;
        --stage) stage=$1 ;; --workspace) workspace=$1 ;; --jobs) jobs=$1 ;;
      esac ;;
    --help|-h)
      echo 'Usage: test-infiltratorfs-boot.sh --source KERNEL-SOURCE --objects COMPILED-OBJECTS --stage NATIVE-STAGE --workspace DIRECTORY [--jobs N] [--install-deps]'
      echo 'Real QEMU/OVMF: Boot loads Kernel and initramfs from Format 0.19 InfiltratorFS; guest mounts/reads/writes that filesystem with an ABI-matching native .ko.'
      echo 'Uses disposable regular-file images only; no host boot or drive changes.'
      exit 0 ;;
    *) fail "Unsupported argument: $1" ;;
  esac
  shift
done
[[ "$source" == /* && -f "$source/Makefile" ]] || fail 'Absolute compiled Kernel source required'
[[ "$objects" == /* && -f "$objects/include/config/kernel.release" ]] || fail 'Absolute compiled kernel objects required'
[[ "$stage" == /* && -d "$stage/System/Kernel" ]] || fail 'Absolute verified native Kernel stage required'
[[ "$workspace" == /* && "$workspace" != / && -d "$workspace" && -w "$workspace" ]] || fail 'Writable absolute trial workspace required'
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail 'Invalid parallel jobs'
[[ $(cat "$objects/include/config/kernel.release") == "$version-infiltrator" ]] || fail 'Wrong compiled InfiltratorOS ABI'
kernel="$stage/System/Kernel/Images/InfiltratorOS-$version.img"
config="$stage/System/Kernel/Images/InfiltratorOS-$version.config"
module_root="$stage/System/Kernel/Modules/InfiltratorOS-$version/kernel"
[[ -s "$kernel" && -s "$config" && -d "$module_root" ]] || fail 'Missing staged Kernel image/config/module tree'
if (( install_deps )); then
  # Installation is explicit via the dedicated trial .run, not a side effect
  # of the normal kernel installer. No disk/boot/EFI packages are configured.
  command -v apt-get >/dev/null || fail 'Automatic trial prerequisites require apt-get'
  apt=( )
  if (( EUID != 0 )); then
    command -v sudo >/dev/null || fail 'sudo is required for trial dependencies'
    apt=(sudo)
  fi
  "${apt[@]}" apt-get update ||
    fail 'Cannot refresh trial build dependency metadata'
  "${apt[@]}" apt-get install -y --no-install-recommends \
    build-essential cmake git wget python3 file busybox-static \
    gnu-efi ovmf qemu-system-x86 qemu-utils dosfstools mtools zstd \
    libssl-dev pkg-config liblz4-dev ||
    fail 'Cannot install QEMU/UEFI/filesystem trial prerequisites'
fi
for dep in git cmake make gcc g++ wget dpkg-deb sha256sum python3 \
  qemu-system-x86_64 mkfs.fat mcopy mmd modinfo zstd; do
  command -v "$dep" >/dev/null || fail "Missing trial prerequisite: $dep"
done
[[ -r /usr/share/OVMF/OVMF_CODE_4M.fd || -r /usr/share/OVMF/OVMF_CODE.fd ]] || fail 'Missing QEMU OVMF firmware'
busybox=$(command -v busybox || :)
[[ -n "$busybox" && -s "$busybox" ]] || fail 'Static BusyBox is required'
if command -v file >/dev/null; then
  file "$busybox" | grep -Fq 'statically linked' || fail 'Install busybox-static for the guest'
fi
trial=$(mktemp -d "$workspace/Boot-InfiltratorFS-Kernel.XXXXXXXX") || fail 'Cannot allocate trial workspace'
log "Preserved evidence: $trial"
fs="$trial/InfiltratorFS"
# Use the exact InfiltratorFS revision whose EFI and native module suites passed.
fs_sha=460a192b98e435120d8ad4bc2461663dd37e8fbb
os_sha=c1c928e309511796387a70fb81b944bfef5f26b3
git init -q -b main "$fs"
git -C "$fs" remote add origin https://github.com/Infiltrator-Projects/InfiltratorFS.git
git -C "$fs" fetch --no-tags --depth 1 origin "$fs_sha" ||
  fail 'Cannot download pinned InfiltratorFS source'
git -C "$fs" checkout --detach -q FETCH_HEAD
[[ $(git -C "$fs" rev-parse HEAD) == "$fs_sha" ]] || fail 'InfiltratorFS source mismatch'
git -C "$fs" submodule update --init --recursive || fail 'Missing required filesystem submodules'
log 'Acquiring exact InfiltratorOS native directory layout and real resources'
os_source="$trial/InfiltratorOS"
git init -q -b main "$os_source"
git -C "$os_source" remote add origin https://github.com/Infiltrator-Projects/InfiltratorOS.git
git -C "$os_source" fetch --no-tags --depth 1 origin "$os_sha" ||
  fail 'Cannot download pinned InfiltratorOS resource source'
git -C "$os_source" checkout --detach -q FETCH_HEAD
[[ $(git -C "$os_source" rev-parse HEAD) == "$os_sha" ]] ||
  fail 'InfiltratorOS resources source mismatch'
[[ -s "$os_source/assets/fonts/SHA256SUMS" &&
   -s "$os_source/assets/icons/PART_SHA256SUMS" &&
   -s "$os_source/assets/infiltratoros.png" ]] ||
  fail 'Native InfiltratorOS resources missing'
log 'Compiling the real InfiltratorFS Format 0.19 EFI reader'
make -C "$fs/uefi/filesystems" -f Make.gnuefi ARCH=x86_64 \
  INFS_UEFI_TRACE=1 -j "$jobs" > "$trial/UEFI-build.log" 2>&1 || {
  tail -n 70 "$trial/UEFI-build.log" >&2; fail 'InfiltratorFS EFI driver build failed';
}
driver="$fs/uefi/filesystems/InfiltratorFS_x64.efi"
[[ -s "$driver" ]] || fail 'No real InfiltratorFS EFI driver'
log 'Building canonical InfiltratorFS formatter and portable writer'
cmake -S "$fs" -B "$trial/FilesystemBuild" -DCMAKE_BUILD_TYPE=Release \
  > "$trial/CMake.log" 2>&1 || {
  tail -n 70 "$trial/CMake.log" >&2; fail 'Filesystem CMake configure failed';
}
cmake --build "$trial/FilesystemBuild" --parallel "$jobs" \
  --target mkfs.infilfs infilfs-tool > "$trial/FilesystemBuild.log" 2>&1 || {
  tail -n 70 "$trial/FilesystemBuild.log" >&2; fail 'Filesystem userspace build failed';
}
log 'Building actual InfiltratorFS Linux .ko against compiled InfiltratorOS Kernel'
make -C "$source" O="$objects" M="$fs/kernel" -j "$jobs" modules \
  > "$trial/KernelModuleBuild.log" 2>&1 || {
  tail -n 90 "$trial/KernelModuleBuild.log" >&2
  fail 'InfiltratorFS .ko cannot compile against current InfiltratorOS Kernel';
}
module="$fs/kernel/infiltratorfs.ko"
[[ -s "$module" ]] || fail 'No native InfiltratorFS kernel module'
[[ $(modinfo -F vermagic "$module" | awk '{print $1}') == "$version-infiltrator" ]] ||
  fail 'InfiltratorFS module has incompatible ABI'
boot_version=0.1.40
boot_pkg="infiltrator-boot_${boot_version}_amd64.deb"
boot_url="https://github.com/Infiltrator-Projects/Boot/releases/download/v$boot_version"
log "Downloading checksum-verified Boot $boot_version"
wget -q -O "$trial/$boot_pkg" "$boot_url/$boot_pkg" || fail 'Boot download failed'
wget -q -O "$trial/BOOT-SHA256SUMS.txt" "$boot_url/SHA256SUMS.txt" ||
  fail 'Boot checksum inventory download failed'
# Match exactly one package name and a complete SHA-256, never a substring.
awk -v package="$boot_pkg" '
  $2 == package && length($1) == 64 && $1 !~ /[^0123456789abcdef]/ {
    print $1 "  " $2; matches++
  }
  END { if (matches != 1) exit 1 }
' "$trial/BOOT-SHA256SUMS.txt" > "$trial/boot-verify.txt" ||
  fail 'Boot package checksum missing, repeated or invalid'
(cd "$trial" && sha256sum -c boot-verify.txt) || fail 'Boot integrity verification failed'
mkdir -p "$trial/Boot"
dpkg-deb -x "$trial/$boot_pkg" "$trial/Boot"
boot="$trial/Boot/usr/lib/infiltrator-boot/EFI/BOOT/BOOTX64.EFI"
[[ -s "$boot" ]] || fail 'Boot EFI executable not found in official package'
# Preserve the cross-repository input identities alongside the boot serial logs.
# Never mistake a passed fixed-revision integration test for qualification of
# newer, unpinned source revisions.
cat > "$trial/SourceRevisions.txt" <<EOF
Boot_version=$boot_version
Boot_package_sha256=$(sha256sum "$trial/$boot_pkg" | awk '{print $1}')
InfiltratorFS_commit=$fs_sha
InfiltratorOS_resources_commit=$os_sha
Kernel_product_release=$version-infiltrator
Kernel_source_commit=$(git -C "$root" rev-parse HEAD 2>/dev/null || printf 'unavailable')
EOF
log 'QEMU/OVMF: Boot must read BOTH real kernel and initramfs from InfiltratorFS'
python3 -u "$root/tests/infiltratorfs-native-boot.py" \
  --boot "$boot" --driver "$driver" --kernel "$kernel" \
  --module "$module" --module-root "$module_root" --kernel-config "$config" \
  --busybox "$busybox" --mkfs "$trial/FilesystemBuild/mkfs.infilfs" \
  --fs-tool "$trial/FilesystemBuild/infilfs-tool" \
  --os-source "$os_source" \
  --output "$trial/VirtualMachine" > "$trial/Trial.log" 2>&1 || {
  tail -n 120 "$trial/Trial.log" >&2
  fail "Actual 3-way VM trial FAILED; all logs/images remain at $trial";
}
grep -Fq 'INFS_BOOT_KERNEL_FILESYSTEM_PASS' "$trial/VirtualMachine/serial.log" ||
  fail 'Guest kernel did not certify the three-project handoff'
grep -Fq 'INFS_OS_TREE_RESOURCE_VERIFY_PASS' "$trial/VirtualMachine/serial.log" ||
  fail 'Guest did not verify native OS files after mount'
grep -Fq 'INFS_OS_TREE_RESOURCE_VERIFY_PASS' "$trial/VirtualMachine/serial-reboot.log" ||
  fail 'Guest did not verify native OS files after reboot'
log "PASS: Boot loaded actual kernel from InfiltratorFS, then native .ko mounted/read/wrote it. Evidence: $trial"
