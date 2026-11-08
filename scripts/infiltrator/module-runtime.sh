#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Linux-compatible InfiltratorOS runtime module discovery and activation.
# The physical modules stay in /System/Kernel; an ephemeral indexed view
# under /run is used by kmod. No host /lib/modules tree is changed.
set -euo pipefail
fail() { printf 'InfiltratorOS module runtime: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'InfiltratorOS module runtime: %s\n' "$*" >&2; }
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
[[ -r "$script_dir/VERSION" ]] || fail 'Missing installed runtime VERSION'
version=$(tr -d '\r\n' < "$script_dir/VERSION")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid product version: $version"
release="$version"
kernel_root=$(cd "$script_dir/../.." && pwd -P)
module_root="$kernel_root/Modules/InfiltratorOS-$version"
provider_root="$kernel_root/Filesystems"
firmware_root="$kernel_root/Firmware"
runtime_root=${INFILTRATOROS_MODULE_VIEW_ROOT:-/run/infiltratoros-kernel}
[[ "$runtime_root" == /* && "$runtime_root" != / && ! -L "$runtime_root" ]] || fail 'Invalid runtime view root'
[[ -d "$module_root/kernel" && ! -L "$module_root" ]] || fail "Native module tree missing: $module_root"
for command_name in depmod modprobe modinfo find ln mktemp xargs; do
  command -v "$command_name" >/dev/null || fail "Missing native runtime dependency: $command_name"
done
# Only a running InfiltratorOS kernel can have its kernel module helper set.
check_running() {
  [[ $(uname -r) == "$release" ]] ||
    fail "Running kernel $(uname -r) is not $release; refusing to load or activate modules"
  [[ -z ${INFILTRATOROS_MODULE_VIEW_ROOT:-} ]] ||
    fail 'Runtime-root override is only permitted for safe preparation and inspection'
}
# The view contains symlinks to the original compiled .ko files. Dependency
# files are generated in the view, NOT in the native module package tree.
prepare() {
  mkdir -p -- "$runtime_root" || fail "Cannot create runtime module view: $runtime_root"
  local staging target file relative basename item vermagic abi provider_count=0 core_count=0
  staging=$(mktemp -d "$runtime_root/view.XXXXXXXX") || fail 'Cannot allocate runtime view'
  trap 'if [[ -n ${staging:-} && -d $staging ]]; then rm -rf -- "$staging"; fi' EXIT
  target="$staging/lib/modules/$release"
  mkdir -p -- "$target"
  declare -A names=()
  # Validate all core module vermagic values in batches, avoiding thousands
  # of modinfo processes during the first kernel module request.
  local check_file="$staging/vermagic.txt"
  find "$module_root/kernel" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name '*.ko.gz' \) -print0 |
    xargs -0 -r -n 64 modinfo -F vermagic > "$check_file" ||
    fail 'One or more native kernel modules failed vermagic inspection'
  while IFS= read -r vermagic; do
    abi=${vermagic%% *}
    [[ "$abi" == "$release" ]] || fail "Kernel module has ABI '$abi', expected '$release'"
    core_count=$((core_count + 1))
  done < "$check_file"
  (( core_count > 0 )) || fail 'Compiled kernel has no usable .ko modules'
  while IFS= read -r basename; do
    names["${basename%%.ko*}"]=1
  done < <(find "$module_root/kernel" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name '*.ko.gz' \) -printf '%f\n')
  # Keep the core module hierarchy intact, with only one directory symlink.
  # depmod traverses it, but writes indexes solely into the /run view.
  ln -s -- "$module_root/kernel" "$target/kernel"
  for item in modules.order modules.builtin modules.builtin.modinfo; do
    if [[ -f "$module_root/$item" ]]; then
      ln -s -- "$module_root/$item" "$target/$item"
    fi
  done
  # Filesystem-*.ko adapters are transitional, architecture-specific code.
  # Only matching vermagic is admitted; legacy 6.12.107 adapters stay inert.
  if [[ -d "$provider_root" && ! -L "$provider_root" ]]; then
    mkdir -p -- "$target/updates/infiltrator-filesystems"
    while IFS= read -r -d '' file; do
      basename=${file##*/}
      if [[ -n ${names["${basename%%.ko*}"]+set} ]]; then
        log "Skipping filesystem adapter already supplied by the core kernel: $basename"
        continue
      fi
      vermagic=$(modinfo -F vermagic "$file" 2>/dev/null) || {
        log "Skipping unreadable filesystem adapter: $basename"; continue;
      }
      abi=${vermagic%% *}
      if [[ "$abi" != "$release" ]]; then
        log "Skipping incompatible filesystem adapter $basename (ABI $abi; needs $release)"
        continue
      fi
      ln -s -- "$file" "$target/updates/infiltrator-filesystems/$basename"
      names["${basename%%.ko*}"]=1
      provider_count=$((provider_count + 1))
    done < <(find "$provider_root" -maxdepth 1 -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name '*.ko.gz' \) -print0)
  fi
  depmod -b "$staging" "$release" || fail 'Failed to index native module dependencies and aliases'
  [[ -s "$target/modules.dep.bin" && -s "$target/modules.alias.bin" ]] || fail 'Missing indexed native module dependencies/aliases'
  # Atomic publication: concurrent modprobe calls always see a complete view.
  local link_tmp
  link_tmp="$runtime_root/.current.$$"
  [[ ! -e "$link_tmp" && ! -L "$link_tmp" ]] || fail 'Conflicting module view link'
  ln -s -- "${staging##*/}" "$link_tmp"
  mv -Tf -- "$link_tmp" "$runtime_root/current"
  log "Indexed $core_count kernel and $provider_count compatible filesystem modules for $release"
  log "Native module view: $runtime_root/current (original files unchanged)"
  staging=
  trap - EXIT
}
mode=${1:-}
case "$mode" in
  prepare)
    (( $# == 1 )) || fail 'Usage: module-runtime prepare'
    prepare ;;
  activate)
    (( $# == 1 )) || fail 'Usage: module-runtime activate'
    check_running
    (( EUID == 0 )) || fail 'Kernel module helper activation requires root'
    prepare
    [[ -w /proc/sys/kernel/modprobe ]] || fail 'Kernel module helper sysctl is unavailable'
    printf '%s\n' "$script_dir/modprobe" > /proc/sys/kernel/modprobe
    if [[ -d "$firmware_root" && -w /sys/module/firmware_class/parameters/path ]]; then
      printf '%s\n' "$firmware_root" > /sys/module/firmware_class/parameters/path
      log "Firmware lookup root: $firmware_root"
    else
      log 'Firmware class path not configurable; firmware loading requires boot-time integration'
    fi
    log "Activated automatic kernel module lookup via $script_dir/modprobe" ;;
  resolve)
    (( $# >= 2 )) || fail 'Usage: module-runtime resolve MODULE_OR_ALIAS'
    shift
    [[ -L "$runtime_root/current" ]] || prepare
    modprobe -d "$runtime_root/current" -S "$release" --show-depends -- "$@" ;;
  status)
    printf 'product_version=%s\nkernel_release=%s\nrunning_kernel=%s\nmodule_source=%s\nfilesystem_module_source=%s\nfilesystem_so_source=/System/Filesystems (userspace/UEFI only)\nmodule_view=%s\n' \
      "$version" "$release" "$(uname -r)" "$module_root" "$provider_root" "$runtime_root/current" ;;
  -h|--help|help)
    printf 'Usage: modprobe {prepare|activate|resolve MODULE|status|<modprobe flags and module>}\n'
    printf 'prepare builds a /run-only kmod index; activate requires the native kernel.\n' ;;
  *)
    # Kernel request_module() passes "-q -- MODALIAS" to this helper.
    # A direct modprobe invocation accepts the same kmod arguments.
    check_running
    [[ -L "$runtime_root/current" ]] || prepare
    exec modprobe -d "$runtime_root/current" -S "$release" "$@" ;;
esac
