#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Install correctly built native Kernel packages without using dpkg -i,
# Debian hooks, /boot, Linux /lib/modules, EFI or the current running kernel.
set -euo pipefail
fail() { printf 'InfiltratorOS Kernel install: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'InfiltratorOS Kernel install: %s\n' "$*" >&2; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
version=$(tr -d '\r\n' < "$root/VERSION")
packages=
install_root=${INFILTRATOROS_INSTALL_ROOT:-/}
replace_existing=0
while (( $# )); do
  case "$1" in
    --replace-existing) replace_existing=1 ;;
    --packages|--install-root)
      opt=$1; shift; (( $# )) || fail "Missing argument for $opt"
      case "$opt" in
        --packages) packages=$1 ;;
        --install-root) install_root=$1 ;;
      esac ;;
    --help|-h)
      echo 'Usage: install-native.sh --packages ABSOLUTE_DIR [--install-root /] [--replace-existing]'
      echo 'Installs three verified native /System/Kernel package payloads; does not configure or activate a bootloader.'
      echo '--replace-existing: archive the previous same-version kernel files before repair.'
      exit 0 ;;
    *) fail "Unsupported option: $1" ;;
  esac
  shift
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid product version'
[[ "$packages" == /* && -d "$packages" && ! -L "$packages" ]] || fail 'Packages must be an existing absolute directory'
[[ "$install_root" == /* && -d "$install_root" && ! -L "$install_root" ]] ||
  fail 'Install root must be an existing absolute non-symlink directory'
for cmd in dpkg-deb tar awk rsync sha256sum mktemp find; do
  command -v "$cmd" >/dev/null || fail "Missing utility: $cmd"
done
packages=$(cd "$packages" && pwd -P)
install_root=$(cd "$install_root" && pwd -P)
image_pkg="infiltratoros-kernel-image-$version"
header_pkg="infiltratoros-kernel-headers-$version"
debug_pkg="infiltratoros-kernel-image-$version-dbg"
[[ -s "$packages/SHA256SUMS-InfiltratorOS-Kernel-$version.txt" ]] ||
  fail 'Fresh compiler package checksum manifest missing'
(cd "$packages" && sha256sum --quiet -c "SHA256SUMS-InfiltratorOS-Kernel-$version.txt") ||
  fail 'Compiler package checksum verification failed'
temp_base=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temp_base" == /* && "$temp_base" != / && -d "$temp_base/Kernel" ]] ||
  fail 'Missing native /Temporary workspace'
workspace=$(mktemp -d "$temp_base/Kernel/.NativeInstall-$version.XXXXXXXX")
# An explicitly requested repair is transactional: prior same-version files
# are moved into /Temporary and restored if the replacement cannot complete.
rollback_needed=0
installation_started=0
backup_dir=
moved_paths=()
managed_paths=()
installation_exit() {
  status=$?
  if (( status != 0 && rollback_needed )); then
    log "Repair failed; restoring previous native kernel files from $backup_dir"
    if (( installation_started )); then
      for rel in "${managed_paths[@]}"; do
        "${writer[@]}" rm -rf -- "$target/$rel" ||
          log "WARNING: could not remove partial replacement $target/$rel"
      done
    fi
    for rel in "${moved_paths[@]}"; do
      if [[ -e "$backup_dir/$rel" || -L "$backup_dir/$rel" ]]; then
        "${writer[@]}" install -d -m 0755 "$(dirname "$target/$rel")" &&
        "${writer[@]}" mv -- "$backup_dir/$rel" "$target/$rel" ||
          log "WARNING: recovery required for $rel; original remains at $backup_dir/$rel"
      fi
    done
  fi
  log "Temporary installation verification workspace: $workspace"
}
trap installation_exit EXIT
mkdir -p "$workspace/unpacked" "$workspace/controls"
abi=
for pkg in "$image_pkg" "$header_pkg" "$debug_pkg"; do
  files=( "$packages"/"${pkg}"_*.deb )
  (( ${#files[@]} == 1 )) && [[ -s "${files[0]}" ]] ||
    fail "Expected exactly one compiled native Debian package for $pkg"
  deb="${files[0]}"
  [[ $(dpkg-deb -f "$deb" Package) == "$pkg" ]] ||
    fail "Unexpected package name in $deb"
  [[ $(dpkg-deb -f "$deb" Version) == "$version-4" ]] ||
    fail "Expected native revision $version-4 in $deb"
  thisabi=$(dpkg-deb -f "$deb" X-InfiltratorOS-Module-ABI)
  [[ "$thisabi" == "$version" ]] ||
    fail "Invalid kernel module ABI '$thisabi' in $deb; expected $version (not upstream Linux 7.0.14)"
  if [[ -z "$abi" ]]; then abi=$thisabi; else
    [[ "$abi" == "$thisabi" ]] || fail 'Mixed kernel module ABIs in installer'
  fi
  # Check actual archive members. No /boot, /usr or /lib path is accepted.
  if ! dpkg-deb --fsys-tarfile "$deb" | tar -tf - |
    awk '
      $0 == "./" || $0 == "./System/" || $0 == "./System/Kernel/" { next }
      /^\.\/System\/Kernel\// {
        if ($0 ~ /(^|\/)\.\.(\/|$)/) { bad=1; print "Traversal: " $0 > "/dev/stderr" }
        next
      }
      { bad=1; print "Unsafe package path: " $0 > "/dev/stderr" }
      END {exit bad}
    '; then
    fail "Not a native /System/Kernel-only package: $deb"
  fi
  dpkg-deb -e "$deb" "$workspace/controls/$pkg"
  for hook in preinst postinst prerm postrm; do
    [[ ! -e "$workspace/controls/$pkg/$hook" ]] ||
      fail "Unexpected kernel lifecycle hook in $pkg: $hook"
  done
  dpkg-deb -x "$deb" "$workspace/unpacked" ||
    fail "Cannot extract $deb into native installation workspace"
done
native="$workspace/unpacked/System/Kernel"
[[ -s "$native/Images/InfiltratorOS-$version.img" ]] ||
  fail 'Freshly compiled native kernel image is missing'
[[ -d "$native/Modules/InfiltratorOS-$version" ]] ||
  fail 'Freshly compiled native module tree is missing'
[[ -d "$native/Headers/InfiltratorOS-$version" ]] ||
  fail 'Freshly generated native developer headers are missing'
[[ -d "$native/Debug/InfiltratorOS-$version" ]] ||
  fail 'Freshly compiled native debug symbols are missing'
[[ -x "$native/Runtime/InfiltratorOS-$version/modprobe" ]] ||
  fail 'Native compiled kernel module helper is missing'
[[ -x "$native/Runtime/InfiltratorOS-$version/verify-host-drivers" &&
   ! -L "$native/Runtime/InfiltratorOS-$version/verify-host-drivers" ]] ||
  fail 'Native hardware driver verifier is missing'
[[ -s "$native/Runtime/InfiltratorOS-$version/VERSION" ]] ||
  fail 'Native module helper version is missing'
found_module=$(find "$native/Modules/InfiltratorOS-$version" -type f \
  \( -name '*.ko' -o -name '*.ko.*' \) -print -quit)
[[ -n "$found_module" ]] || fail 'No compiled native kernel modules'
[[ ! -e "$workspace/unpacked/boot" && ! -e "$workspace/unpacked/usr" &&
   ! -e "$workspace/unpacked/lib" ]] ||
  fail 'Extracted payload contains non-native Linux installation paths'

target="$install_root/System/Kernel"
[[ ! -L "$install_root/System" && ! -L "$target" ]] ||
  fail 'Refusing to install through a symlinked System or Kernel directory'
if [[ "$install_root" == / ]]; then
  log 'Installing exclusively below /System/Kernel (sudo required); no bootloader or kernel activation'
  writer=()
  if (( EUID != 0 )); then writer=(sudo); fi
  rsync_owner=(--chown=root:root --chmod=go-w)
else
  log "Installing to isolated test root $install_root (no sudo)"
  writer=()
  rsync_owner=()
fi
# Native kernel repair is deliberately opt-in. No unrelated filesystem
# providers, firmware, or directories outside these versioned paths move.
managed_paths=(
  "Images/InfiltratorOS-$version.img"
  "Images/InfiltratorOS-$version.config"
  "Images/InfiltratorOS-$version.map"
  "Modules/InfiltratorOS-$version"
  "Headers/InfiltratorOS-$version"
  "Debug/InfiltratorOS-$version"
  "Runtime/InfiltratorOS-$version"
)
for parent in Images Modules Headers Debug Runtime; do
  [[ ! -L "$target/$parent" ]] ||
    fail "Refusing symlinked native installation parent: $target/$parent"
done
if [[ $install_root == / ]]; then
  # The running kernel can invoke its native helper as root. Seal each
  # parent top-down before inspecting or copying executable payloads.
  for parent in "$install_root/System" "$target" "$target"/{Images,Modules,Headers,Debug,Runtime}; do
    [[ ! -L $parent ]] || fail "Refusing symlinked system path: $parent"
    "${writer[@]}" install -d -m 0755 -o root -g root -- "$parent" ||
      fail "Cannot secure native kernel directory: $parent"
  done
fi
collision=0
for rel in "${managed_paths[@]}"; do
  [[ ! -L "$target/$rel" ]] || fail "Refusing symlinked kernel path $target/$rel"
  if [[ -e "$target/$rel" ]]; then
    if (( ! replace_existing )); then
      fail "Refusing to overwrite existing native kernel installation: $target/$rel (rerun with --replace-existing to archive and repair)"
    fi
    collision=1
  fi
done
if (( collision )); then
  backup_parent="$temp_base/Kernel/Backups"
  mkdir -p -- "$backup_parent" || fail "Cannot create protected kernel backup parent"
  backup_dir=$(mktemp -d "$backup_parent/InfiltratorOS-$version-previous.XXXXXXXX") ||
    fail "Cannot create native repair backup"
  rollback_needed=1
  for rel in "${managed_paths[@]}"; do
    if [[ -e "$target/$rel" ]]; then
      mkdir -p -- "$backup_dir/$(dirname "$rel")" || fail "Cannot prepare backup for $rel"
      moved_paths+=("$rel")
      "${writer[@]}" mv -- "$target/$rel" "$backup_dir/$rel" ||
        fail "Could not preserve prior installed kernel file $target/$rel"
    fi
  done
  log "Preserved prior native kernel files under $backup_dir"
fi
"${writer[@]}" install -d -m 0755 "$target"
installation_started=1

# The checked file set is new and versioned. --ignore-existing also defends
# against unexpected preexisting files appearing between checking and copy.
"${writer[@]}" rsync -a "${rsync_owner[@]}" --ignore-existing -- "$native/" "$target/" ||
  fail 'Native kernel installation copy failed'
# Verify each installed regular file, without ever removing unrelated files.
while IFS= read -r -d '' file; do
  rel=${file#"$native/"}
  if [[ -f "$file" ]]; then
    [[ -f "$target/$rel" ]] || fail "Missing installed kernel file $rel"
    cmp -s -- "$file" "$target/$rel" ||
      fail "Installed kernel file differs from compiler output: $rel"
  fi
done < <(find "$native" -type f -print0)
rollback_needed=0
log "PASS: freshly compiled native Kernel $version packages installed at $target"
if [[ -n "$backup_dir" ]]; then log "Previous native files preserved at $backup_dir"; fi
log 'No changes to Mint /boot, /lib/modules, /usr/src, EFI, NVRAM, or running kernel.'
log 'BOOT discovery and host hardware verification occur at the next boot.'
