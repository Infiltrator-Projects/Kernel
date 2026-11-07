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
while (( $# )); do
  case "$1" in
    --packages|--install-root)
      opt=$1; shift; (( $# )) || fail "Missing argument for $opt"
      case "$opt" in
        --packages) packages=$1 ;;
        --install-root) install_root=$1 ;;
      esac ;;
    --help|-h)
      echo 'Usage: install-native.sh --packages ABSOLUTE_DIR [--install-root /]'
      echo 'Installs three verified native /System/Kernel package payloads; does not configure or activate a bootloader.'
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
trap 'log "Temporary installation verification workspace: $workspace"' EXIT
mkdir -p "$workspace/unpacked" "$workspace/controls"
abi=
for pkg in "$image_pkg" "$header_pkg" "$debug_pkg"; do
  files=( "$packages"/"${pkg}"_*.deb )
  (( ${#files[@]} == 1 )) && [[ -s "${files[0]}" ]] ||
    fail "Expected exactly one compiled native Debian package for $pkg"
  deb="${files[0]}"
  [[ $(dpkg-deb -f "$deb" Package) == "$pkg" ]] ||
    fail "Unexpected package name in $deb"
  [[ $(dpkg-deb -f "$deb" Version) == "$version-3" ]] ||
    fail "Expected native revision $version-3 in $deb"
  thisabi=$(dpkg-deb -f "$deb" X-InfiltratorOS-Module-ABI)
  [[ "$thisabi" == "$version-infiltrator" ]] ||
    fail "Invalid kernel module ABI '$thisabi' in $deb; expected $version-infiltrator (not upstream Linux 7.0.14)"
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
  writer=(sudo)
else
  log "Installing to isolated test root $install_root (no sudo)"
  writer=()
fi
# Prevent overwriting any earlier native kernel files. The root may contain
# other Filesystems/format modules which must be left strictly alone.
for rel in \
  "Images/InfiltratorOS-$version.img" \
  "Images/InfiltratorOS-$version.config" \
  "Images/InfiltratorOS-$version.map" \
  "Modules/InfiltratorOS-$version" \
  "Headers/InfiltratorOS-$version" \
  "Debug/InfiltratorOS-$version"; do
  if [[ -e "$target/$rel" || -L "$target/$rel" ]]; then
    fail "Refusing to overwrite existing native kernel installation: $target/$rel"
  fi
done
"${writer[@]}" install -d -m 0755 "$target"
# The checked file set is new and versioned. --ignore-existing also defends
# against unexpected preexisting files appearing between checking and copy.
"${writer[@]}" rsync -a --ignore-existing -- "$native/" "$target/" ||
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
log "PASS: freshly compiled native Kernel $version packages installed at $target"
log 'No changes to Mint /boot, /lib/modules, /usr/src, EFI, NVRAM, or running kernel.'
log 'Boot activation, module-loader runtime and full OS boot remain separate development qualifications.'
