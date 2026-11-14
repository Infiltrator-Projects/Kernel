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
[[ "$release" =~ ^[a-zA-Z0-9._+-]+$ ]] || fail "Unrecognised kernel release: $release"
# Historical 0.1.1-1/-2 artifacts had the imported Linux 7.0.14
# release string. A new independently compiled native -3 package
# must instead use the actual InfiltratorOS kernel release.
expected_native_release="$component_version"
[[ -f "$objects/.config" ]] || fail 'Kernel build configuration is missing'
packages=$(cd "$packages" && pwd -P)
objects=$(cd "$objects" && pwd -P)
if ! mkdir -p "$(dirname "$output")"; then
  if [[ "$output" == "$native_workspace/Staging/"* ]]; then
    fail "Cannot create native staging workspace under $native_workspace. This is a directory permission issue, not a kernel build failure. A system administrator can provision only that Kernel directory for your account: sudo install -d -m 0750 -o \"$(id -un)\" -g \"$(id -gn)\" \"$native_workspace\". Do not run this staging script with sudo or change ownership of the shared /Temporary/InfiltratorOS parent."
  fi
  fail "Cannot create staging parent: $(dirname "$output")"
fi
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
    # Existing 0.1.1 packages were built with X-... source fields;
    # dpkg-gencontrol silently omits those fields from the binary control.
    # Do not reject an otherwise valid, previously compiled package solely
    # because the optional metadata was not copied across.
    package_version=$(dpkg-deb -f "$deb" Version) || fail "Cannot inspect native package version: $deb"
    if [[ "$package_version" == "$component_version-4" && "$release" != "$expected_native_release" ]]; then
      fail "New native package cannot stage an inherited Linux release '$release'; expected $expected_native_release"
    fi
    abi=$(dpkg-deb -f "$deb" X-InfiltratorOS-Module-ABI) || fail "Cannot inspect package ABI: $deb"
    if [[ -n "$abi" && "$abi" != "$release" ]]; then
      fail "Native image package declares ABI $abi but built kernel is $release"
    fi
    if [[ -z "$abi" ]]; then
      log "Package lacks the optional binary ABI field; validating actual boot image and module payload before staging"
    fi
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
# The original -1 packages install to Linux /boot and /lib/modules.
# The corrected -2 native packages install directly into /System/Kernel.
# Accept both as *inputs* without ever reinstalling or altering the host.
native_source="$tmp/extracted/System/Kernel"
if [[ -f "$native_source/Images/InfiltratorOS-$component_version.img" ]]; then
  image="$native_source/Images/InfiltratorOS-$component_version.img"
  module_path="$native_source/Modules/InfiltratorOS-$component_version"
  [[ -d "$module_path" ]] || fail 'Native image package lacks its native module tree'
  cp -a -- "$image" "$tmp/result/System/Kernel/Images/InfiltratorOS-$component_version.img"
  if [[ -f "$native_source/Images/InfiltratorOS-$component_version.config" ]]; then
    cp -a -- "$native_source/Images/InfiltratorOS-$component_version.config" "$tmp/result/System/Kernel/Images/InfiltratorOS-$component_version.config"
  else
    cp -a -- "$objects/.config" "$tmp/result/System/Kernel/Images/InfiltratorOS-$component_version.config"
  fi
  if [[ -f "$native_source/Images/InfiltratorOS-$component_version.map" ]]; then
    cp -a -- "$native_source/Images/InfiltratorOS-$component_version.map" "$tmp/result/System/Kernel/Images/InfiltratorOS-$component_version.map"
  fi
  log 'Staging correctly native-packaged /System/Kernel image and module paths'
else
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
  log 'Reading historical Linux-path -1 package as a compatibility input only'
fi
[[ -n "$module_path" ]] ||
  fail "Package $(basename "${images[0]}") has no modules under the exact compiled ABI $release; refusing to stage it"
# A directory and release-shaped image alone are insufficient to validate a
# compiled module package. Require at least one loadable module in the tree.
found_module=$(find "$module_path" -type f \( -name '*.ko' -o -name '*.ko.*' \) -print -quit)
[[ -n "$found_module" ]] ||
  fail "Package contains no loadable modules under ABI $release"
log "Verified exact compiled image and module payload for ABI $release"
# Native namespace is product-versioned. Module internals remain Linux-
# compatible pending a qualified native loader; exact ABI is metadata only.
mkdir -p "$tmp/result/System/Kernel/Modules/InfiltratorOS-$component_version"
rsync -a --exclude='/build' --exclude='/source' "$module_path/" \
  "$tmp/result/System/Kernel/Modules/InfiltratorOS-$component_version/"
# Native packages include a version-bound userspace loader alongside the
# driver indexes. Staging must preserve that exact runtime as well, otherwise
# the staged image cannot exercise the same autoload path as installation.
# Historical packages without a Runtime directory remain readable inputs.
runtime_path="$native_source/Runtime/InfiltratorOS-$component_version"
runtime_manifest=not-included
if [[ -e "$runtime_path" || -L "$runtime_path" ]]; then
  [[ -d "$runtime_path" && ! -L "$runtime_path" &&
     -f "$runtime_path/modprobe" && ! -L "$runtime_path/modprobe" && -x "$runtime_path/modprobe" &&
     -f "$runtime_path/VERSION" && ! -L "$runtime_path/VERSION" &&
     $(<"$runtime_path/VERSION") == "$component_version" ]] ||
    fail 'Native kernel module runtime is incomplete or has the wrong version'
  mkdir -p "$tmp/result/System/Kernel/Runtime/InfiltratorOS-$component_version"
  rsync -a -- "$runtime_path/" "$tmp/result/System/Kernel/Runtime/InfiltratorOS-$component_version/"
  runtime_manifest="System/Kernel/Runtime/InfiltratorOS-$component_version/modprobe"
fi
# The two reserved namespaces must remain format-owner controlled.
cat > "$tmp/result/STAGING-STATUS.txt" <<TEXT
product=InfiltratorOS Kernel
product_version=$component_version
kernel_release=$release
transitional_module_abi=$release
module_abi=$release
boot_install=not-performed
host_install=not-performed
secure_boot=not-qualified
module_runtime_path=$runtime_manifest
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
log "The exact kernel/module ABI is recorded in STAGING-STATUS.txt; native directories use product version $component_version"
log 'Not installed; no boot configuration, system files or running kernel were modified.'
