#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Stage a successfully compiled kernel in the documented InfiltratorOS
# hierarchy. Never installs anything on the host or updates the bootloader.
set -euo pipefail
fail() { printf 'Kernel stage: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'Kernel stage: %s\n' "$*" >&2; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
component_version=$(tr -d '\r\n' < "$root/VERSION")
[[ "$component_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Kernel stage: ERROR: invalid component VERSION" >&2; exit 1; }
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] || fail "Invalid native Temporary root: $temporary_root"
native_workspace="$temporary_root/Kernel"
packages="$native_workspace/Packages"
if [[ ! -d "$packages" && -d "$root/dist" ]]; then
  # Existing first-build products stay usable, but no new files are added
  # to the historical dist/ directory.
  packages="$root/dist"
  log "Reading preserved legacy packages from $packages"
fi
objects="$native_workspace/Build/obj"
if [[ ! -f "$objects/include/config/kernel.release" && -d "$root/.native-build/obj" ]]; then
  objects="$root/.native-build/obj"
fi
# Older builds compiled in-source because their parent `make` exported
# sub_make_done. The build writes its successfully completed objtree here,
# allowing native staging to use the actual image/config/System.map without
# discarding the saved compiler outputs or assuming a newer out-of-tree build.
for record in "$native_workspace/Build/last-completed-objtree" "$root/.native-build/last-completed-objtree"; do
  [[ -f "$record" ]] || continue
  IFS= read -r saved_objects < "$record" || :
  case "$saved_objects" in
    "$root"|"$root/.native-build/obj"|"$native_workspace/Build/obj")
      objects="$saved_objects"; break ;;
    *) fail "Unexpected recorded object directory: $saved_objects" ;;
  esac
done
# Stage into a distinct product-versioned tree, preserving the successful
# transitional binary baseline in dist/native/ untouched.
output="$native_workspace/Staging/InfiltratorOS-$component_version"
replace_existing=0
while (( $# )); do
  case "$1" in
    --packages|--objects|--output)
      option=$1; shift; (( $# )) || fail "Missing argument to $option"
      case "$option" in
        --packages) packages=$1 ;;
        --objects) objects=$1 ;;
        --output) output=$1 ;;
      esac ;;
    --replace) replace_existing=1 ;;
    --help|-h)
      echo "Usage: stage-native.sh [--packages DIR] [--objects DIR] [--output DIR] [--replace]"
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
legacy_images=()
for deb in "$packages"/*.deb; do
  package=$(dpkg-deb -f "$deb" Package) || fail "Cannot inspect $deb"
  if [[ "$package" == "infiltratoros-kernel-image-$component_version" ]]; then
    abi=$(dpkg-deb -f "$deb" X-InfiltratorOS-Module-ABI) || fail "Cannot inspect package ABI: $deb"
    [[ "$abi" == "$release" ]] || fail "Native image package ABI ($abi) does not match built kernel ($release)"
    images+=("$deb")
  elif [[ "$package" == "linux-image-$release" || "$package" == "linux-image-unsigned-$release" ]]; then
    # Read-only compatibility with the already successful Linux-named baseline.
    legacy_images+=("$deb")
  fi
done
if (( ${#images[@]} == 0 )); then
  images=("${legacy_images[@]}")
  log 'Using preserved transitional image package; native package renaming not yet built'
fi
(( ${#images[@]} == 1 )) || fail "Expected one matching compiled image for $release; found ${#images[@]}"
base=$(dirname "$output")
tmp=$(mktemp -d "$base/.native-stage.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/extracted" "$tmp/result/System/Kernel/Images" "$tmp/result/System/Kernel/Modules" \
  "$tmp/result/System/Kernel/Filesystems" "$tmp/result/System/Kernel/Firmware"
log "Unpacking locally compiled package: $(basename "${images[0]}")"
dpkg-deb -x "${images[0]}" "$tmp/extracted"
image="$tmp/extracted/boot/vmlinuz-$release"
[[ -f "$image" ]] || fail "Compiled boot image not found at /boot/vmlinuz-$release in image package"
cp -a -- "$image" "$tmp/result/System/Kernel/Images/InfiltratorOS-$component_version.img"
cp -a -- "$objects/.config" "$tmp/result/System/Kernel/Images/InfiltratorOS-$component_version.config"
if [[ -f "$objects/System.map" ]]; then
  cp -a -- "$objects/System.map" "$tmp/result/System/Kernel/Images/InfiltratorOS-$component_version.map"
fi
module_path=''
for prefix in lib usr/lib; do
  if [[ -d "$tmp/extracted/$prefix/modules/$release" ]]; then
    module_path="$tmp/extracted/$prefix/modules/$release"
    break
  fi
done
if [[ -n "$module_path" ]]; then
  # Native namespace is product-versioned. Module internals remain Linux-
  # compatible pending a qualified native loader; exact ABI is metadata only.
  mkdir -p "$tmp/result/System/Kernel/Modules/InfiltratorOS-$component_version"
  rsync -a --exclude='/build' --exclude='/source' "$module_path/" \
    "$tmp/result/System/Kernel/Modules/InfiltratorOS-$component_version/"
fi
# The two reserved namespaces must remain format-owner controlled.
cat > "$tmp/result/STAGING-STATUS.txt" <<TEXT
product=InfiltratorOS Kernel
product_version=$component_version
kernel_release=$release
transitional_module_abi=$release
boot_install=not-performed
host_install=not-performed
secure_boot=not-qualified
module_runtime_path=not-integrated
module_namespace=System/Kernel/Modules/InfiltratorOS-$component_version
staging_location=Temporary
runtime_status=transitional-not-bootable
filesystem_provider_modules=not-included
source_image_package=$(basename "${images[0]}")
TEXT
(
  cd "$tmp/result"
  find System -type f -print0 | sort -z | xargs -0 -r sha256sum > SHA256SUMS.txt
)
[[ -s "$tmp/result/System/Kernel/Images/InfiltratorOS-$component_version.img" ]] || fail 'Staged image is empty'
[[ -s "$tmp/result/SHA256SUMS.txt" ]] || fail 'Staged checksum manifest is empty'
if [[ -e "$output" ]]; then
  (( replace_existing )) || fail "Output already exists: $output (preserved; use --replace only if intentional)"
  [[ -d "$output" && ! -L "$output" ]] || fail 'Existing output is not a regular directory'
  mv -- "$output" "$tmp/previous"
fi
if ! mv -- "$tmp/result" "$output"; then
  if [[ -d "$tmp/previous" ]]; then mv -- "$tmp/previous" "$output"; fi
  fail 'Could not publish staged native tree'
fi
log "Staged InfiltratorOS Kernel $component_version under $output/System/Kernel/"
log "The inherited module ABI remains in STAGING-STATUS.txt, not the native directory names"
log 'Not installed; no boot configuration, system files or running kernel were modified.'
