#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Stage a successfully compiled kernel in the documented InfiltratorOS
# hierarchy. Never installs anything on the host or updates the bootloader.
set -euo pipefail
fail() { printf 'Kernel stage: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'Kernel stage: %s\n' "$*" >&2; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
packages="$root/dist"
objects="$root/.native-build/obj"
output="$root/dist/native"
while (( $# )); do
  case "$1" in
    --packages|--objects|--output)
      option=$1; shift; (( $# )) || fail "Missing argument to $option"
      case "$option" in
        --packages) packages=$1 ;;
        --objects) objects=$1 ;;
        --output) output=$1 ;;
      esac ;;
    --help|-h)
      echo "Usage: stage-native.sh [--packages DIR] [--objects DIR] [--output DIR]"
      echo 'Stages kernel images and built modules for InfiltratorOS, without installation.'
      exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
  shift
done
[[ -d "$packages" && -d "$objects" ]] || fail 'Build outputs are missing; the full kernel compilation must succeed first'
[[ -s "$objects/include/config/kernel.release" ]] || fail 'The configured kernel release file is missing'
release=$(cat "$objects/include/config/kernel.release")
[[ "$release" =~ ^[a-zA-Z0-9._+-]+$ && "$release" == *infiltrator* ]] || fail "Unrecognised kernel release: $release"
[[ -f "$objects/.config" ]] || fail 'Kernel build configuration is missing'
packages=$(cd "$packages" && pwd -P)
objects=$(cd "$objects" && pwd -P)
mkdir -p "$(dirname "$output")"
output=$(cd "$(dirname "$output")" && pwd -P)/$(basename "$output")
[[ "$output" != / && "$output" != /System* && "$output" != /boot* ]] || fail 'Refusing to stage directly on the installed host'
[[ "$output" != "$packages" && "$output" != "$objects" ]] || fail 'Output must not replace the build inputs'
[[ ! -L "$output" ]] || fail 'Output location must not be a symbolic link'
shopt -s nullglob
images=()
for deb in "$packages"/*.deb; do
  package=$(dpkg-deb -f "$deb" Package) || fail "Cannot inspect $deb"
  if [[ "$package" == "linux-image-$release" || "$package" == "linux-image-unsigned-$release" ]]; then
    images+=("$deb")
  fi
done
(( ${#images[@]} == 1 )) || fail "Expected one compiled image package for $release; found ${#images[@]}"
base=$(dirname "$output")
tmp=$(mktemp -d "$base/.native-stage.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/extracted" "$tmp/result/System/Kernel/Images" "$tmp/result/System/Kernel/Modules" \
  "$tmp/result/System/Kernel/Filesystems" "$tmp/result/System/Kernel/Firmware"
log "Unpacking locally compiled package: $(basename "${images[0]}")"
dpkg-deb -x "${images[0]}" "$tmp/extracted"
image="$tmp/extracted/boot/vmlinuz-$release"
[[ -f "$image" ]] || fail "Compiled boot image not found at /boot/vmlinuz-$release in image package"
cp -a -- "$image" "$tmp/result/System/Kernel/Images/InfiltratorOS-$release.img"
cp -a -- "$objects/.config" "$tmp/result/System/Kernel/Images/InfiltratorOS-$release.config"
if [[ -f "$objects/System.map" ]]; then
  cp -a -- "$objects/System.map" "$tmp/result/System/Kernel/Images/InfiltratorOS-$release.map"
fi
module_path=''
for prefix in lib usr/lib; do
  if [[ -d "$tmp/extracted/$prefix/modules/$release" ]]; then
    module_path="$tmp/extracted/$prefix/modules/$release"
    break
  fi
done
if [[ -n "$module_path" ]]; then
  mkdir -p "$tmp/result/System/Kernel/Modules/$release"
  rsync -a --exclude='/build' --exclude='/source' "$module_path/" \
    "$tmp/result/System/Kernel/Modules/$release/"
fi
# The two reserved namespaces must remain format-owner controlled.
cat > "$tmp/result/STAGING-STATUS.txt" <<TEXT
product=InfiltratorOS Kernel
kernel_release=$release
boot_install=not-performed
host_install=not-performed
secure_boot=not-qualified
module_runtime_path=not-integrated
filesystem_provider_modules=not-included
source_image_package=$(basename "${images[0]}")
TEXT
(
  cd "$tmp/result"
  find System -type f -print0 | sort -z | xargs -0 -r sha256sum > SHA256SUMS.txt
)
[[ -s "$tmp/result/System/Kernel/Images/InfiltratorOS-$release.img" ]] || fail 'Staged image is empty'
[[ -s "$tmp/result/SHA256SUMS.txt" ]] || fail 'Staged checksum manifest is empty'
if [[ -e "$output" ]]; then
  [[ -d "$output" && ! -L "$output" ]] || fail 'Existing output is not a regular directory'
  mv -- "$output" "$tmp/previous"
fi
if ! mv -- "$tmp/result" "$output"; then
  if [[ -d "$tmp/previous" ]]; then mv -- "$tmp/previous" "$output"; fi
  fail 'Could not publish staged native tree'
fi
log "Staged InfiltratorOS kernel $release under $output/System/Kernel/"
log 'Not installed; no boot configuration, system files or running kernel were modified.'
