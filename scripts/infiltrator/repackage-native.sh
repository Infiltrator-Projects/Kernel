#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Repackage the proven compiled Kernel 0.1.0 as native /System/Kernel .debs.
# Never recompiles, installs, cleans, deletes, or modifies original artifacts.
set -euo pipefail
fail() { printf 'Native Kernel package: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'Native Kernel package: %s\n' "$*" >&2; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
version=$(tr -d '\r\n' < "$root/VERSION")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid product version'
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
archive="$HOME/InfiltratorOS-Kernel-Archive/InfiltratorOS-Kernel-$version"
packages="$archive/OriginalBuildOutputs"
stage="$archive/StagedKernel"
out_parent="$temporary_root/Kernel/Packages/NativeLayout"
while (( $# )); do
  case "$1" in
    --packages|--stage|--output)
      option=$1; shift; (( $# )) || fail "Missing $option argument"
      case "$option" in
        --packages) packages=$1 ;;
        --stage) stage=$1 ;;
        --output) out_parent=$1 ;;
      esac ;;
    --help|-h)
      echo 'Usage: repackage-native.sh [--packages ABS_DIR] [--stage ABS_DIR] [--output ABS_DIR]'
      echo 'Repacks the already compiled revision -1 image, headers and debug into native-layout revision -2 packages.'
      echo 'Never builds a kernel, installs packages or changes the host.'
      exit 0 ;;
    *) fail "Unexpected option: $1" ;;
  esac
  shift
done
[[ "$packages" == /* && "$stage" == /* && "$out_parent" == /* && "$out_parent" != / ]] ||
  fail 'Use absolute source and destination paths'
[[ -d "$packages" && -d "$stage" && -s "$stage/SHA256SUMS.txt" && -s "$stage/STAGING-STATUS.txt" ]] ||
  fail 'Archived compiled packages or staged kernel manifest missing'
for cmd in dpkg-deb sha256sum rsync mktemp tar find awk; do
  command -v "$cmd" >/dev/null || fail "Missing utility: $cmd"
done
abi=$(sed -n 's/^kernel_release=//p' "$stage/STAGING-STATUS.txt")
[[ "$abi" =~ ^[A-Za-z0-9.+-]+$ && "$abi" == *infiltrator* ]] ||
  fail "Invalid compiled module ABI: $abi"
grep -Fxq "product_version=$version" "$stage/STAGING-STATUS.txt" ||
  fail 'Wrong staged product version'
log 'Verifying checksum manifest of original compiled/staged Kernel'
(cd "$stage" && sha256sum --quiet -c SHA256SUMS.txt) ||
  fail 'Original stage checksums failed'
[[ -s "$stage/System/Kernel/Images/InfiltratorOS-$version.img" ]] ||
  fail 'Compiled native-staged kernel image missing'
[[ -d "$stage/System/Kernel/Modules/InfiltratorOS-$version" ]] ||
  fail 'Compiled native-staged module tree missing'
find "$stage/System/Kernel/Modules/InfiltratorOS-$version" -type f \
  \( -name '*.ko' -o -name '*.ko.*' \) -print -quit | grep -q . ||
  fail 'No compiled loadable kernel modules found'

image_pkg="infiltratoros-kernel-image-$version"
header_pkg="infiltratoros-kernel-headers-$version"
debug_pkg="infiltratoros-kernel-image-$version-dbg"
declare -A originals=()
shopt -s nullglob
for deb in "$packages"/*.deb; do
  name=$(dpkg-deb -f "$deb" Package) || fail "Cannot inspect compiled package $deb"
  case "$name" in
    "$image_pkg"|"$header_pkg"|"$debug_pkg")
      deb_version=$(dpkg-deb -f "$deb" Version)
      [[ "$deb_version" == "$version-1" ]] ||
        fail "Refusing unknown original package revision $deb_version in $deb"
      [[ -z "${originals[$name]:-}" ]] || fail "Duplicate source package $name"
      originals["$name"]="$deb" ;;
  esac
done
for name in "$image_pkg" "$header_pkg" "$debug_pkg"; do
  [[ -n "${originals[$name]:-}" ]] || fail "Missing previously compiled package: $name"
done

mkdir -p "$out_parent" || fail "Cannot access native package destination $out_parent"
out_parent=$(cd "$out_parent" && pwd -P)
packages=$(cd "$packages" && pwd -P)
stage=$(cd "$stage" && pwd -P)
[[ "$out_parent" != "$packages" && "$out_parent" != "$stage" &&
   "$out_parent" != /System* && "$out_parent" != /boot* ]] ||
  fail 'Refusing to write into sources, installed /System or /boot'
final="$out_parent/InfiltratorOS-$version"
[[ ! -e "$final" && ! -L "$final" ]] ||
  fail "Native package set already exists: $final; refusing to overwrite"
work=$(mktemp -d "$out_parent/.InfiltratorOS-$version-native.Incomplete.XXXXXXXX") ||
  fail 'Cannot create isolated packaging workspace'
log "Incomplete workspace (retained if interrupted): $work"
mkdir -p "$work/extracted" "$work/release"

make_control() {
  local payload=$1 name=$2 description=$3
  mkdir -p "$payload/DEBIAN"
  cat > "$payload/DEBIAN/control" <<EOF
Package: $name
Version: $version-2
Section: kernel
Priority: optional
Architecture: amd64
Maintainer: InfiltratorOS Kernel <noreply@infiltratoros.invalid>
X-InfiltratorOS-Kernel-Version: $version
X-InfiltratorOS-Module-ABI: $abi
Description: $description
 Previously compiled InfiltratorOS Kernel, packaged for /System/Kernel only.
 No maintainer hooks, host bootloader modifications or kernel replacement.
EOF
}

log 'Preparing image and modules from existing SHA-verified native stage'
image_payload="$work/$image_pkg"
mkdir -p "$image_payload/System/Kernel"
rsync -a "$stage/System/Kernel/" "$image_payload/System/Kernel/" ||
  fail 'Failed to copy verified kernel image/modules'
[[ ! -e "$image_payload/System/Kernel/Modules/InfiltratorOS-$version/build" ]] ||
  fail 'Unexpected development build link in staged runtime modules'
make_control "$image_payload" "$image_pkg" "InfiltratorOS Kernel $version image and runtime modules"

log 'Reusing already compiled header package without rebuilding'
dpkg-deb -x "${originals[$header_pkg]}" "$work/extracted/headers" ||
  fail 'Cannot unpack original headers'
header_input="$work/extracted/headers/usr/src/linux-headers-$abi"
[[ -d "$header_input" ]] || fail "Original headers not found under $header_input"
headers_payload="$work/$header_pkg"
mkdir -p "$headers_payload/System/Kernel/Headers/InfiltratorOS-$version" \
  "$headers_payload/System/Kernel/Modules/InfiltratorOS-$version"
rsync -a "$header_input/" "$headers_payload/System/Kernel/Headers/InfiltratorOS-$version/" ||
  fail 'Failed to copy original compiled headers'
ln -s "/System/Kernel/Headers/InfiltratorOS-$version" \
  "$headers_payload/System/Kernel/Modules/InfiltratorOS-$version/build"
make_control "$headers_payload" "$header_pkg" "InfiltratorOS Kernel $version build and development headers"

log 'Reusing already compiled debug package and its internal symbol links'
dpkg-deb -x "${originals[$debug_pkg]}" "$work/extracted/debug" ||
  fail 'Cannot unpack original debug symbols'
debug_input="$work/extracted/debug/usr/lib/debug"
[[ -d "$debug_input/lib/modules/$abi" ]] ||
  fail 'Missing debug symbols for the exact compiled kernel ABI'
debug_payload="$work/$debug_pkg"
mkdir -p "$debug_payload/System/Kernel/Debug/InfiltratorOS-$version"
rsync -a "$debug_input/" "$debug_payload/System/Kernel/Debug/InfiltratorOS-$version/" ||
  fail 'Failed to copy original compiled debug symbols'
make_control "$debug_payload" "$debug_pkg" "InfiltratorOS Kernel $version debugging symbols"

for name in "$image_pkg" "$header_pkg" "$debug_pkg"; do
  file="$work/release/${name}_${version}-2_amd64.deb"
  log "Creating $name; all payload paths must start with /System/Kernel"
  dpkg-deb --build "$work/$name" "$file" >/dev/null ||
    fail "Could not package $name"
  [[ $(dpkg-deb -f "$file" Package) == "$name" ]] ||
    fail "Wrong binary package identity: $name"
  [[ $(dpkg-deb -f "$file" Version) == "$version-2" ]] ||
    fail "Wrong native revision: $name"
  [[ $(dpkg-deb -f "$file" X-InfiltratorOS-Module-ABI) == "$abi" ]] ||
    fail "Compiled module ABI lost from $name"
  if ! dpkg-deb --fsys-tarfile "$file" | tar -tf - |
    awk '
      $0 == "./" || $0 == "./System/" || $0 == "./System/Kernel/" { next }
      /^\.\/System\/Kernel\// { next }
      { print "NON-NATIVE DEBIAN PAYLOAD: " $0 > "/dev/stderr"; wrong=1 }
      END { exit wrong }
    '; then
    fail "Package still installs outside /System/Kernel: $name"
  fi
done
{
  echo "InfiltratorOS Kernel $version native-layout Debian packages"
  echo "TransitionalModuleABI=$abi"
  echo "NewPackageRevision=$version-2"
  echo "Recompiled=no"
  echo "InstalledOnHost=no"
  echo "BootloaderModified=no"
  echo "OriginalPackages=$packages"
  echo "VerifiedStage=$stage"
} > "$work/release/NATIVE-PACKAGING-STATUS.txt"
(
  cd "$work/release"
  sha256sum ./*.deb > SHA256SUMS.txt
  sha256sum --quiet -c SHA256SUMS.txt
) || fail 'New native packages failed checksum validation'
[[ ! -e "$final" && ! -L "$final" ]] || fail "Existing packages preserved: $final"
mv -T "$work/release" "$final" || fail 'Could not publish new native package set'
log "PASS: three native /System/Kernel-only revision -2 packages: $final"
log 'Original compiled binaries, historical packages, proven first-boot archives and Mint remain untouched.'
