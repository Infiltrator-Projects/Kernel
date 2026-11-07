#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Audit exact files Debian Kbuild left in the user's home directory.
# Relocate only identified kernel outputs into the existing archive namespace.
set -euo pipefail
fail() { printf 'Kernel home audit: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'Kernel home audit: %s\n' "$*" >&2; }

root=$(cd "$(dirname "$0")/../.." && pwd -P)
version=$(tr -d '\r\n' < "$root/VERSION")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid Kernel VERSION: $version"
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
stage="$temporary_root/Kernel/Staging/InfiltratorOS-$version/STAGING-STATUS.txt"
[[ -s "$stage" ]] || fail "Missing previously successful stage metadata: $stage"
release=$(sed -n 's/^kernel_release=//p' "$stage")
[[ "$release" =~ ^[[:alnum:].+-]+$ ]] || fail "Invalid recorded kernel release: $release"

mode=preview
case "${1:-}" in
  '') ;;
  --relocate) mode=relocate; shift ;;
  --help|-h)
    echo "Usage: bash scripts/infiltrator/audit-home-artifacts.sh [--relocate]"
    echo 'By default only reports identified home-directory kernel packages and metadata.'
    echo '--relocate moves precisely identified files into the durable Kernel archive, retaining checksums.'
    exit 0 ;;
  *) fail "Unknown argument: $1" ;;
esac
(( $# == 0 )) || fail 'Unexpected extra arguments'

declare -a candidates=()
declare -a unclassified=()
shopt -s nullglob
for f in "$HOME"/*; do
  [[ -f "$f" && ! -L "$f" ]] || continue
  name=$(basename "$f")
  accepted=0
  case "$name" in
    infiltratoros-kernel-image-"$version"_*.deb|infiltratoros-kernel-image-"$version"-dbg_*.deb|infiltratoros-kernel-headers-"$version"_*.deb|linux-image-"$release"_*.deb|linux-image-"$release"-dbg_*.deb|linux-image-unsigned-"$release"_*.deb|linux-headers-"$release"_*.deb)
      pkg=$(dpkg-deb -f "$f" Package 2>/dev/null) || pkg=
      case "$pkg" in
        "infiltratoros-kernel-image-$version"|"infiltratoros-kernel-image-$version-dbg"|"infiltratoros-kernel-headers-$version"|"linux-image-$release"|"linux-image-unsigned-$release"|"linux-image-$release-dbg"|"linux-headers-$release")
          accepted=1 ;;
      esac ;;
    infiltratoros-kernel_"$version"-*.changes|infiltratoros-kernel_"$version"-*.buildinfo)
      grep -Fxq 'Source: infiltratoros-kernel' "$f" && accepted=1 || : ;;
  esac
  if (( accepted )); then
    candidates+=("$f")
  else
    case "$name" in
      linux-*.deb|linux-*.changes|linux-*.buildinfo|infiltratoros-*.deb|infiltratoros-*.changes|infiltratoros-*.buildinfo)
        unclassified+=("$f") ;;
    esac
  fi
done

log "Kernel package ABI: $release; component version: $version"
log "Approved home-directory Kbuild files: ${#candidates[@]}"
for f in "${candidates[@]}"; do
  printf 'APPROVED  %10s bytes  %s\n' "$(stat -c %s -- "$f")" "$f"
done
if (( ${#unclassified[@]} )); then
  log 'Other Linux-looking files NOT automatically approved for moving:'
  printf 'UNCLASSIFIED %s\n' "${unclassified[@]}"
fi
if [[ "$mode" == preview ]]; then
  log 'READ-ONLY preview complete. No files were changed.'
  log 'Use --relocate only if the approved names are the Kernel outputs you want removed from Home.'
  exit 0
fi
(( ${#candidates[@]} )) || { log 'No approved loose Kernel files to relocate'; exit 0; }
# Keep the completed snapshot immutable: use an independent sibling folder.
archive_root="$HOME/InfiltratorOS-Kernel-Archive"
[[ -s "$archive_root/InfiltratorOS-Kernel-$version/SHA256SUMS-Archive.txt" ]] ||
  fail 'Verified 0.1.0 milestone archive not present; refusing to move original files'
target="$archive_root/HistoricalHomeOutputs-$version"
[[ ! -e "$target" && ! -L "$target" ]] ||
  fail "Historical home outputs already preserved at $target; refusing overwrite"
mkdir -p -- "$target" || fail "Could not create $target"
# Hash originals before moving. mv -T is non-overwriting because each
# destination is individually checked; do not delete files.
for f in "${candidates[@]}"; do
  leaf=$(basename "$f")
  [[ ! -e "$target/$leaf" && ! -L "$target/$leaf" ]] ||
    fail "Collision, preserving both source and destination: $target/$leaf"
  digest=$(sha256sum -- "$f" | cut -d' ' -f1)
  mv -T -- "$f" "$target/$leaf" || fail "Could not move: $f"
  actual=$(sha256sum -- "$target/$leaf" | cut -d' ' -f1)
  [[ "$digest" == "$actual" ]] || fail "Hash mismatch after relocating: $leaf"
  log "MOVED AND VERIFIED: $leaf"
done
(
  cd "$target"
  find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -print0 |
    LC_ALL=C sort -z | xargs -0 -r sha256sum > SHA256SUMS.txt
  sha256sum --quiet -c SHA256SUMS.txt
) || fail 'Historical outputs verification failed'
log "PASS: identified files moved out of Home into $target"
log 'Existing 0.1.0 verified archive, native staged kernel, VM evidence, unrelated home files and host installation were not modified.'
