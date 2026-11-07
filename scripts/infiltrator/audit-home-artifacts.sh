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
  --relocate-upstream-remainder) mode=remainder; shift ;;
  --help|-h)
    echo "Usage: bash scripts/infiltrator/audit-home-artifacts.sh [--relocate|--relocate-upstream-remainder]"
    echo 'By default only reports identified home-directory kernel packages and metadata.'
    echo '--relocate moves the original strict approved set into the durable Kernel archive.'
    echo '--relocate-upstream-remainder moves separately verified linux-upstream compatibility files into a NEW child directory.'
    exit 0 ;;
  *) fail "Unknown argument: $1" ;;
esac
(( $# == 0 )) || fail 'Unexpected extra arguments'

declare -a candidates=()
declare -a unclassified=()
declare -a upstream_remainder=()
shopt -s nullglob

# The first successful clean-up already archived the compiled upstream
# Linux image .deb. Its embedded package VERSION is our precise provenance
# for the three remaining upstream packaging outputs, without guessing
# from unrelated filenames in the user home directory.
upstream_version=
archive_root="$HOME/InfiltratorOS-Kernel-Archive"
upstream_baseline=("$archive_root/HistoricalHomeOutputs-$version/linux-image-$release"_*.deb)
if (( ${#upstream_baseline[@]} == 1 )); then
  archive_pkg=$(dpkg-deb -f "${upstream_baseline[0]}" Package 2>/dev/null) || archive_pkg=
  if [[ "$archive_pkg" == "linux-image-$release" ]]; then
    upstream_version=$(dpkg-deb -f "${upstream_baseline[0]}" Version 2>/dev/null) || upstream_version=
  fi
fi
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
    continue
  fi
  upstream_ok=0
  if [[ -n "$upstream_version" ]]; then
    case "$name" in
      "linux-libc-dev_${upstream_version}_amd64.deb")
        pkg=$(dpkg-deb -f "$f" Package 2>/dev/null) || pkg=
        pkg_version=$(dpkg-deb -f "$f" Version 2>/dev/null) || pkg_version=
        [[ "$pkg" == linux-libc-dev && "$pkg_version" == "$upstream_version" ]] && upstream_ok=1 ;;
      "linux-upstream_${upstream_version}_amd64.buildinfo"|"linux-upstream_${upstream_version}_amd64.changes")
        grep -Fxq 'Source: linux-upstream' "$f" &&
        grep -Fxq "Version: $upstream_version" "$f" && upstream_ok=1 || : ;;
    esac
  fi
  if (( upstream_ok )); then
    upstream_remainder+=("$f")
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
if (( ${#upstream_remainder[@]} )); then
  log "Verified upstream Kbuild remainder matched to the previously archived image package: "${#upstream_remainder[@]}" file(s)"
  for f in "${upstream_remainder[@]}"; do
    printf 'APPROVED-UPSTREAM %10s bytes  %s\n' "$(stat -c %s -- "$f")" "$f"
  done
fi
if (( ${#unclassified[@]} )); then
  log 'Other Linux-looking files NOT automatically approved for moving:'
  printf 'UNCLASSIFIED %s\n' "${unclassified[@]}"
fi
if [[ "$mode" == preview ]]; then
  log 'READ-ONLY preview complete. No files were changed.'
  log 'Use --relocate for the original approved set, or --relocate-upstream-remainder for the three verified upstream files.'
  exit 0
fi
if [[ "$mode" == remainder ]]; then
  candidates=("${upstream_remainder[@]}")
fi
(( ${#candidates[@]} )) || { log 'No approved loose Kernel files to relocate'; exit 0; }
# Keep the completed snapshot immutable: use an independent sibling folder.
[[ -s "$archive_root/InfiltratorOS-Kernel-$version/SHA256SUMS-Archive.txt" ]] ||
  fail 'Verified 0.1.0 milestone archive not present; refusing to move original files'
target="$archive_root/HistoricalHomeOutputs-$version"
if [[ "$mode" == remainder ]]; then
  [[ -s "$target/SHA256SUMS.txt" ]] ||
    fail 'The original eight-file historical home archive is not verified and present'
  [[ -n "$upstream_version" ]] || fail 'Cannot prove remaining files match the archived upstream kernel ABI/package version'
  target="$target/UpstreamRemainder"
fi
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
