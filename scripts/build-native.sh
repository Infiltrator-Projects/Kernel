#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Linux Mint / Debian source-first kernel builder. Never installs a kernel.
set -euo pipefail
fail() { echo "Kernel: ERROR: $*" >&2; exit 1; }
log() { echo "Kernel: $*" >&2; }
root=$(cd "$(dirname "$0")/.." && pwd -P)
mode= source_dir= jobs= skip_deps=0
while (( $# )); do
  case "$1" in
    --probe|--configure-only|--build-only) [[ -z "$mode" ]] || fail "Select one mode"; mode=$1 ;;
    --source-dir|--jobs) opt=$1; shift; (( $# )) || fail "Missing $opt argument"
      case "$opt" in --source-dir) source_dir=$1 ;; --jobs) jobs=$1 ;; esac ;;
    --skip-deps) skip_deps=1 ;;
    --help|-h) echo "Usage: build-native.sh --probe | --configure-only | --build-only [--source-dir DIR] [--jobs N] [--skip-deps]"; exit 0 ;;
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
work="$root/.native-build"; out="$root/dist"
mkdir -p "$work" "$out"
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
obj="$work/obj"; mkdir -p "$obj"
cp "$config" "$obj/.config"
# Vendor kernel configurations may reference private/distribution-supplied
# certificate files not carried in the published source package. Never edit
# the installed /boot config or fabricate a certificate to satisfy Kbuild.
bash "$root/scripts/infiltrator/prepare-certificates.sh" "$source_dir" "$obj"
log "Configuring with the running distro defaults"
make -C "$source_dir" O="$obj" LOCALVERSION=-infiltrator olddefconfig
# bindeb-pkg invokes a second kernel make via debian/rules. It consumes
# include/config/auto.conf, not just the edited .config. In incremental
# builds a stale auto.conf can retain the absent Canonical PEM paths, so
# explicitly synchronize and verify the *effective* build configuration
# before touching any more driver objects.
log "Synchronizing Kbuild's generated configuration"
make -C "$source_dir" O="$obj" LOCALVERSION=-infiltrator syncconfig
bash "$root/scripts/infiltrator/verify-certificate-config.sh" "$source_dir" "$obj" "$obj/.config"
release=$(make -s --no-print-directory -C "$source_dir" O="$obj" LOCALVERSION=-infiltrator kernelrelease)
[[ "$release" == *infiltrator* && "$release" != "$running" ]] || fail "Kernel release suffix is not distinct: $release"
log "Generated kernel release: $release"
if [[ "$mode" == --configure-only ]]; then log "Configured at $obj/.config"; exit 0; fi
log "Building Debian packages using $jobs jobs; NO kernel install or reboot"
make -C "$source_dir" O="$obj" LOCALVERSION=-infiltrator -j "$jobs" bindeb-pkg
count=0
: > "$out/SHA256SUMS.txt"
for deb in "$work"/*.deb; do
  [[ -f "$deb" ]] || continue
  name=$(dpkg-deb -f "$deb" Package)
  case "$name" in linux-image-*infiltrator*|linux-headers-*infiltrator*) ;; *) continue ;; esac
  cp "$deb" "$out/"
  (cd "$out" && sha256sum "$(basename "$deb")") >> "$out/SHA256SUMS.txt"
  count=$((count+1))
done
(( count > 0 )) || fail "Build completed but no distinct Infiltrator .deb was found"
{
 echo "running_kernel=$running"
 echo "source_package=$pkg"
 echo "source_version=$ver"
 echo "kernel_release=$release"
 echo "config_sha256=$(sha256sum "$config" | cut -d' ' -f1)"
 echo "installed_kernel=no"
} > "$out/build-provenance.txt"
log "Created $count kernel .deb package(s) in dist/. No kernel was installed."
