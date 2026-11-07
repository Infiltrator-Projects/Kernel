#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Linux Mint / Debian source-first kernel builder. Never installs a kernel.
set -euo pipefail
fail() { echo "Kernel: ERROR: $*" >&2; exit 1; }
log() { echo "Kernel: $*" >&2; }
root=$(cd "$(dirname "$0")/.." && pwd -P)
mode= source_dir= jobs= skip_deps=0 object_dir= packages_dir= fresh_objects=0
while (( $# )); do
  case "$1" in
    --probe|--configure-only|--build-only) [[ -z "$mode" ]] || fail "Select one mode"; mode=$1 ;;
    --source-dir|--jobs|--object-dir|--packages-dir) opt=$1; shift; (( $# )) || fail "Missing $opt argument"
      case "$opt" in --source-dir) source_dir=$1 ;; --jobs) jobs=$1 ;; --object-dir) object_dir=$1 ;; --packages-dir) packages_dir=$1 ;; esac ;;
    --fresh-objects) fresh_objects=1 ;;
    --skip-deps) skip_deps=1 ;;
    --help|-h) echo "Usage: build-native.sh --probe | --configure-only | --build-only [--source-dir DIR] [--jobs N] [--skip-deps] [--object-dir ABS_DIR --packages-dir ABS_DIR --fresh-objects]"; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
  shift
done
[[ -n "$mode" ]] || fail "Select --probe, --configure-only or --build-only"
[[ $(uname -m) == x86_64 ]] || fail "Initial kernel builds support x86_64 only"
. /etc/os-release
case " $ID ${ID_LIKE:-} " in *debian*|*ubuntu*|*linuxmint*) ;; *) fail "Only Debian/Mint/Ubuntu hosts supported initially" ;; esac
running=$(uname -r)
config="/boot/config-$running"
[[ -r "$config" ]] || fail "Running kernel configuration not found: $config"
# Never use the linux-signed-* source package from the signed image.
# The exact installed headers identify the real kernel source.
rec=$(dpkg-query -W -f='${source:Package}|${source:Version}' "linux-headers-$running" 2>/dev/null) || fail "Matching kernel headers are not installed"
IFS='|' read -r pkg ver <<< "$rec"
[[ -n "$pkg" && -n "$ver" ]] || fail "Could not resolve the installed kernel source version"
log "Host: ${PRETTY_NAME:-$ID}"
log "Kernel: $running; source: $pkg=$ver"
log "Configuration: $config; target: native x86_64; original compiler flags"
if [[ "$mode" == --probe ]]; then
  if command -v apt-cache >/dev/null && apt-cache showsrc "$pkg" >/dev/null 2>&1; then
    log "APT source repositories: available"
  else
    log "APT source repositories: missing; enable deb-src for this distribution"
  fi
  exit 0
fi
if (( ! skip_deps )); then
  command -v apt-cache >/dev/null || fail "APT is missing"
  apt-cache showsrc "$pkg" >/dev/null 2>&1 || fail "Enable deb-src repositories and run sudo apt update"
  log "Checking/installing build dependencies; sudo may request approval"
  sudo apt-get install -y --no-install-recommends build-essential bc bison flex fakeroot dwarves libelf-dev libssl-dev rsync dpkg-dev
  sudo apt-get build-dep -y "$pkg"
fi
for tool in make gcc dpkg-deb sha256sum; do command -v "$tool" >/dev/null || fail "Missing $tool"; done
if [[ -n "$jobs" ]]; then
  [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "Invalid --jobs count"
else
  cpus=$(getconf _NPROCESSORS_ONLN)
  mem=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)
  memory_jobs=$((mem / 2097152)); (( memory_jobs > 0 )) || memory_jobs=1
  jobs=$cpus; (( jobs <= memory_jobs )) || jobs=$memory_jobs
fi
# InfiltratorOS owns /Temporary for all uninstalled work and packages.
# Retain historic dist/ and .native-build/ untouched as evidence from the
# first successful baseline; those are never destinations for new outputs.
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] || fail "Invalid native Temporary root: $temporary_root"
native_workspace="$temporary_root/Kernel"
work="$native_workspace/Build"
out="$native_workspace/Packages"
# A truly clean build must use an explicit never-before-used object tree and
# output directory. This is how any Git clone can prove the compiler works;
# none of the previously successful local .o files are required or reused.
if (( fresh_objects )); then
  [[ "$mode" == --build-only && -n "$object_dir" && -n "$packages_dir" ]] ||
    fail '--fresh-objects requires --build-only, --object-dir and --packages-dir'
  [[ "$object_dir" == "$native_workspace/Build/"* &&
     "$packages_dir" == "$native_workspace/Packages/"* ]] ||
    fail 'Fresh object and package directories must be below native /Temporary/InfiltratorOS/Kernel'
  [[ ! -e "$object_dir" && ! -L "$object_dir" ]] ||
    fail "Fresh object directory already exists: $object_dir"
  [[ ! -e "$packages_dir" && ! -L "$packages_dir" ]] ||
    fail "Fresh package directory already exists: $packages_dir"
  out="$packages_dir"
elif [[ -n "$object_dir" || -n "$packages_dir" ]]; then
  fail '--object-dir and --packages-dir require --fresh-objects'
fi
mkdir -p "$work" "$out" || fail "Cannot write $native_workspace; provision the native Temporary directory with user access"
log "Temporary build workspace: $work"
log "Uninstalled package output: $out"
# A Mint baseline kept in Git must not block Debian machines whose running
# kernel has another base version. Prefer matching source, then fetch exact.
matches_running() {
  local dir=$1 file first
  [[ -f "$dir/Makefile" && -d "$dir/scripts/kconfig" ]] || return 1
  # Ubuntu and Debian kernel ABI names need not match the underlying
  # Linux Makefile VERSION.PATCHLEVEL.SUBLEVEL (e.g. Ubuntu 7.0.0-42
  # ships a Linux source Makefile at upstream 7.0.14).
  if [[ -r "$dir/docs/upstream/source-id" ]] &&
     [[ "$(cat "$dir/docs/upstream/source-id")" == "$pkg=$ver" ]]; then
    return 0
  fi
  for file in "$dir/debian.master/changelog" "$dir/debian/changelog"; do
    [[ -r "$file" ]] || continue
    IFS= read -r first < "$file" || :
    [[ "$first" == "$pkg ($ver)"* ]] && return 0
  done
  return 1
}
if [[ -n "$source_dir" ]]; then
  source_dir=$(cd "$source_dir" && pwd -P) || fail "Invalid --source-dir"
elif matches_running "$root"; then
  source_dir="$root"
elif matches_running "$root/src/linux"; then
  source_dir="$root/src/linux"
else
  count=0
  for dir in "$root"/upstream/*/; do
    if matches_running "$dir"; then
      source_dir=$dir; count=$((count+1))
    fi
  done
  if (( count == 0 )); then
    mkdir -p "$work/sources"
    log "Downloading exact distribution kernel source: $pkg=$ver"
    (cd "$work/sources" && apt-get source "$pkg=$ver") || fail "Exact source download failed; check deb-src"
    for dir in "$work"/sources/*/; do
      if [[ -f "$dir/Makefile" && -d "$dir/scripts/kconfig" ]]; then
        source_dir=$dir; count=$((count+1))
      fi
    done
  fi
  (( count == 1 )) || fail "Need exactly one Linux source tree in upstream or the source workspace"
fi
[[ -f "$source_dir/Makefile" && -d "$source_dir/scripts/kconfig" ]] || fail "Not a complete kernel source tree"
v=$(awk '$1=="VERSION" {print $3;exit}' "$source_dir/Makefile")
p=$(awk '$1=="PATCHLEVEL" {print $3;exit}' "$source_dir/Makefile")
s=$(awk '$1=="SUBLEVEL" {print $3;exit}' "$source_dir/Makefile")
base="$v.$p.$s"
matches_running "$source_dir" || fail "Source tree does not match installed source package $pkg=$ver"
log "Upstream kernel code: $base (distribution ABI: $running)"
# Earlier releases were called as a Kbuild recipe and inherited
# sub_make_done=1. Kbuild consequently ignored O= and compiled in the source
# directory. These objects are valuable and must not be silently deleted.
# Continue that *existing* in-tree build until the baseline is qualified;
# new, clean checkouts continue to use .native-build/obj as intended.
obj="$work/obj"
# Existing objects from earlier versions are never discarded merely because
# we relocated *new* build work to /Temporary/InfiltratorOS/Kernel.
if (( ! fresh_objects )) && [[ -f "$root/.native-build/obj/.config" && -f "$root/.native-build/obj/include/config/auto.conf" ]]; then
  obj="$root/.native-build/obj"
  log "Reusing legacy out-of-tree compilation objects; leaving them in place"
fi
if (( ! fresh_objects )) && [[ -f "$source_dir/.config" && -f "$source_dir/include/config/auto.conf" ]]; then
  obj="$source_dir"
  log "Reusing existing in-source compilation objects; no clean or rebuild requested"
fi
if (( fresh_objects )); then
  obj="$object_dir"
  log "Fresh isolated compile: O=$obj; no preserved build objects reused"
fi
# bindeb-pkg writes .deb, .changes and .buildinfo next to the
# Kbuild object tree. When that tree is the repository ~/Kernel itself,
# Kbuild writes directly into ~/ and pollutes the user's home directory.
# The first completed milestone is already preserved; never do another
# packaging run that targets the user's home. A future isolated object
# build must be configured deliberately without moving or cleaning the
# proven in-source baseline.
if [[ "$mode" == --build-only ]]; then
  package_parent=$(dirname "$obj")
  if [[ "$package_parent" == "$HOME" || "$package_parent" == / ]]; then
    fail "Refusing kernel package output in $package_parent. The old in-source build is preserved; use an isolated /Temporary/InfiltratorOS/Kernel/Build object tree for a NEW build. No compilation or package operation started."
  fi
fi
mkdir -p "$obj"
# The imported Linux source Makefile remains 7.0.14, including its
# LINUX_VERSION_CODE and internal compatibility expectations. The independent
# InfiltratorOS release, UTS_RELEASE and module vermagic are 0.1.0-infiltrator.
# Do not pretend this project already has seven major versions.
product_version=$(tr -d '\r\n' < "$root/VERSION")
[[ "$product_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fail "Invalid InfiltratorOS Kernel product VERSION: $product_version"
release_id="$product_version-infiltrator"
if [[ "$obj" == "$source_dir" ]]; then
  kbuild_args=(-C "$source_dir" KERNELRELEASE="$release_id")
else
  kbuild_args=(-C "$source_dir" O="$obj" KERNELRELEASE="$release_id")
fi
cp "$config" "$obj/.config"
# Vendor kernel configurations may reference private/distribution-supplied
# certificate files not carried in the published source package. Never edit
# the installed /boot config or fabricate a certificate to satisfy Kbuild.
bash "$root/scripts/infiltrator/prepare-certificates.sh" "$source_dir" "$obj"
# Compile the InfiltratorOS module helper path into the native kernel.
native_modprobe="/System/Kernel/Runtime/InfiltratorOS-$product_version/modprobe"
"$source_dir/scripts/config" --file "$obj/.config" --set-str MODPROBE_PATH "$native_modprobe"
log "Configuring with the running distro defaults"
bash "$root/scripts/infiltrator/run-kbuild.sh" "${kbuild_args[@]}" olddefconfig
# A fresh kernel make is required at every stage: the outer `make build-only`
# exports sub_make_done=1, which suppresses Kbuild's first-pass O= parsing.
# The run-kbuild helper clears this inherited marker so our object directory
# is actually used, rather than silently writing to the source checkout.
# Kbuild's "prepare" target ensures include/config/auto.conf and
# generated headers are actually materialised, unlike invoking the internal
# syncconfig subtarget directly on every kernel revision. The package step
# recursively runs Kbuild; it must see the same certificate options we checked.
log "Preparing Kbuild's generated configuration and headers"
bash "$root/scripts/infiltrator/run-kbuild.sh" "${kbuild_args[@]}" prepare
bash "$root/scripts/infiltrator/verify-certificate-config.sh" "$source_dir" "$obj" "$obj/.config"
release=$(bash "$root/scripts/infiltrator/run-kbuild.sh" -s --no-print-directory "${kbuild_args[@]}" kernelrelease)
[[ "$release" == "$release_id" && "$release" != "$running" ]] ||
  fail "Generated kernel release '$release' does not match InfiltratorOS '$release_id'"
[[ $(cat "$obj/include/config/kernel.release") == "$release_id" ]] ||
  fail 'Kbuild kernel.release file does not contain the independent InfiltratorOS version'
[[ -f "$obj/include/generated/utsrelease.h" ]] ||
  fail 'Missing compiled UTS release header'
grep -Fqx "#define UTS_RELEASE \"$release_id\"" "$obj/include/generated/utsrelease.h" ||
  fail 'Compiled UTS_RELEASE still contains the imported Linux source version'
grep -Fqx "CONFIG_MODPROBE_PATH=\"$native_modprobe\"" "$obj/include/config/auto.conf" ||
  fail "Compiled kernel has not selected the native InfiltratorOS module helper"
log "Generated InfiltratorOS kernel release and module ABI: $release"
if [[ "$mode" == --configure-only ]]; then log "Configured at $obj/.config"; exit 0; fi
# The first-party native build uses InfiltratorOS's own release and vermagic.
# The imported source's 7.0.14 version remains upstream provenance only;
# never generate native packages with 7.0.14-infiltrator as their ABI.
grep -Fq INFILTRATOROS_NATIVE_PACKAGE "$source_dir/scripts/package/mkdebian" ||
  fail "Selected upstream source has not integrated the InfiltratorOS native package generator"
export INFILTRATOROS_NATIVE_PACKAGE=1 INFILTRATOROS_KERNEL_VERSION="$product_version"
log "Building InfiltratorOS Kernel $product_version (kernel release/module ABI: $release; upstream source: $base) using $jobs jobs; NO kernel install or reboot"
bash "$root/scripts/infiltrator/run-kbuild.sh" "${kbuild_args[@]}" -j "$jobs" bindeb-pkg
count=0
manifest="$out/SHA256SUMS-InfiltratorOS-Kernel-$product_version.txt"
[[ ! -e "$manifest" && ! -L "$manifest" ]] ||
  fail "Existing package checksum manifest preserved: $manifest"
: > "$manifest"
# Kbuild writes its transitional Debian output beside the object tree.
# On the historic in-source build this is the home directory. Copy verified
# new products to native /Temporary; preserve older files rather than
# deleting historical builds or modifying a running compilation.
packages_dir=$(dirname "$obj")
for deb in "$packages_dir"/*.deb; do
  [[ -f "$deb" ]] || continue
  name=$(dpkg-deb -f "$deb" Package)
  case "$name" in
    "infiltratoros-kernel-image-$product_version"|"infiltratoros-kernel-image-$product_version-dbg"|"infiltratoros-kernel-headers-$product_version") ;;
    *) continue ;;
  esac
  abi=$(dpkg-deb -f "$deb" X-InfiltratorOS-Module-ABI)
  [[ "$abi" == "$release_id" ]] || fail "Package ABI mismatch for $deb: $abi (expected $release_id)"
  if (( fresh_objects )); then
    [[ $(dpkg-deb -f "$deb" Version) == "$product_version-4" ]] ||
      fail "Fresh build yielded wrong package revision; expected $product_version-4: $deb"
  fi
  target="$out/$(basename "$deb")"
  if [[ -e "$target" ]]; then
    cmp -s -- "$deb" "$target" || fail "Existing package preserved (different bytes): $target"
  else
    cp -- "$deb" "$target" || fail "Could not copy compiled package into Temporary: $target"
  fi
  (cd "$out" && sha256sum "$(basename "$deb")") >> "$manifest"
  count=$((count+1))
done
if (( fresh_objects )); then
  (( count == 3 )) || fail "Fresh build expected exact image, headers and debug packages; found $count"
else
  (( count > 0 )) || fail "No InfiltratorOS Kernel $product_version packages were generated"
fi
if (( ! fresh_objects )); then
  printf '%s\n' "$obj" > "$work/last-completed-objtree"
fi
{
 echo "object_tree=$obj"
 echo "running_kernel=$running"
 echo "source_package=$pkg"
 echo "source_version=$ver"
 echo "kernel_release=$release"
 echo "component_version=$product_version"
 echo "upstream_linux_source_version=$base"
 echo "config_sha256=$(sha256sum "$config" | cut -d' ' -f1)"
 echo "installed_kernel=no"
 echo "fresh_objects=$fresh_objects"
 echo "source_commit=$(git -C "$root" rev-parse HEAD 2>/dev/null || echo exported-git-archive)"
} > "$out/build-provenance-infiltratoros-kernel-$product_version.txt"
log "Created $count InfiltratorOS Kernel $product_version .deb package(s) in $out. No kernel was installed."
