#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Preserve the actual successful native Kernel milestone outside /Temporary.
# Read-only source inspection; never install, delete or overwrite a milestone.
set -euo pipefail

fail() { printf 'InfiltratorOS Kernel archive: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'InfiltratorOS Kernel archive: %s\n' "$*" >&2; }

root=$(cd "$(dirname "$0")/../.." && pwd -P)
version=$(tr -d '\r\n' < "$root/VERSION")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fail "Invalid Kernel VERSION: $version"
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] ||
  fail "Invalid Temporary root: $temporary_root"

packages="$root/dist"
stage="$temporary_root/Kernel/Staging/InfiltratorOS-$version"
evidence=
archive_root="$HOME/InfiltratorOS-Kernel-Archive"
while (( $# )); do
  case "$1" in
    --evidence|--packages|--stage|--archive-root)
      option=$1; shift; (( $# )) || fail "Missing argument for $option"
      case "$option" in
        --evidence) evidence=$1 ;;
        --packages) packages=$1 ;;
        --stage) stage=$1 ;;
        --archive-root) archive_root=$1 ;;
      esac ;;
    --help|-h)
      echo 'Usage: preserve-milestone.sh --evidence ABSOLUTE-DIRECTORY [--packages DIR] [--stage DIR] [--archive-root DIR]'
      echo 'Copies and verifies the three packages, historical dist outputs, staged kernel and successful QEMU evidence.'
      echo 'The source data is left unchanged; an existing final archive is never overwritten.'
      exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
  shift
done
[[ "$evidence" == /* && -d "$evidence" ]] ||
  fail 'Specify the existing successful VM evidence directory with --evidence /absolute/path'
[[ "$archive_root" == /* && "$archive_root" != / ]] ||
  fail "Archive root must be an absolute non-root path: $archive_root"
[[ -d "$packages" && -d "$stage" ]] ||
  fail "Build outputs or native staged image are missing"
[[ -s "$stage/SHA256SUMS.txt" ]] || fail 'Staged kernel manifest missing'
[[ -s "$evidence/Test.log" && -s "$evidence/VirtualMachine/serial.log" ]] ||
  fail 'VM test evidence or guest serial log missing'
grep -Fq 'BOOT-FAT16-SO-LINUX-HANDOFF-PASS' "$evidence/Test.log" ||
  fail 'The selected VM test evidence did not pass'
[[ -s "$stage/System/Kernel/Images/InfiltratorOS-$version.img" ]] ||
  fail "No staged kernel $version image"
for cmd in rsync dpkg-deb sha256sum find sort xargs du df git; do
  command -v "$cmd" >/dev/null || fail "Required tool missing: $cmd"
done

log 'Verifying the original staged artifact checksums'
(cd "$stage" && sha256sum --quiet -c SHA256SUMS.txt) ||
  fail 'Staged source artifact checksum verification failed'

# Confirm all three *actual* InfiltratorOS .deb packages, not only the
# development test's synthetic image package.
declare -A found=()
shopt -s nullglob
for deb in "$packages"/*.deb; do
  pkg=$(dpkg-deb -f "$deb" Package) || fail "Cannot read Debian package: $deb"
  found["$pkg"]="$deb"
done
for pkg in "infiltratoros-kernel-image-$version" \
           "infiltratoros-kernel-headers-$version" \
           "infiltratoros-kernel-image-$version-dbg"; do
  [[ -n "${found[$pkg]:-}" ]] || fail "Missing previously built package: $pkg"
done

mkdir -p -- "$archive_root" || fail "Cannot create archive root: $archive_root"
archive_root=$(cd "$archive_root" && pwd -P)
final="$archive_root/InfiltratorOS-Kernel-$version"
[[ ! -e "$final" && ! -L "$final" ]] ||
  fail "Previous verified archive preserved at $final; refusing to overwrite it"

# Build a distinct incomplete directory. If any copy/check fails, keep that
# directory for inspection; do not delete it or touch the source artifacts.
partial=$(mktemp -d "$archive_root/.InfiltratorOS-Kernel-$version.Incomplete.XXXXXXXX") ||
  fail 'Could not allocate archival workspace'
trap 'printf "InfiltratorOS Kernel archive: incomplete copy, if any, remains at: %s\n" "$partial" >&2' ERR
mkdir -p "$partial/OriginalBuildOutputs" "$partial/StagedKernel" \
  "$partial/VirtualBootEvidence" "$partial/BuildLogs"

log 'Copying original successful Debian packages and historical build outputs'
rsync -aS -- "$packages/" "$partial/OriginalBuildOutputs/" ||
  fail 'Copying historical build outputs failed; original files were not altered'
log 'Copying the SHA-256 verified native Kernel staging tree'
rsync -aS -- "$stage/" "$partial/StagedKernel/" ||
  fail 'Copying staged kernel failed; original files were not altered'
log 'Copying successful QEMU/OVMF evidence and disposable test media'
rsync -aS -- "$evidence/" "$partial/VirtualBootEvidence/" ||
  fail 'Copying VM test evidence failed; original files were not altered'

for log_file in "$HOME/Kernel-build-next.log" "$HOME/Kernel-build-native-$version.log"; do
  if [[ -f "$log_file" ]]; then
    cp -p -- "$log_file" "$partial/BuildLogs/" ||
      fail "Copying build log failed: $log_file"
  fi
done

{
  echo "Product=InfiltratorOS Kernel"
  echo "ComponentVersion=$version"
  echo "ArchivedUTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "SourceRepository=https://github.com/Infiltrator-Projects/Kernel"
  echo "SourceCommit=$(git -C "$root" rev-parse HEAD)"
  echo "SourceBranch=$(git -C "$root" branch --show-current)"
  echo "OriginalBuildOutputs=$packages"
  echo "OriginalStaging=$stage"
  echo "OriginalVirtualBootEvidence=$evidence"
  echo "BootEvidence=BOOT-FAT16-SO-LINUX-HANDOFF-PASS"
  echo "RuntimeQualification=QEMU/OVMF-initramfs-only"
  echo "NativeModuleABI=not-yet-qualified"
  echo "InstalledOnHost=no"
} > "$partial/Archive-Record.txt"

log 'Verifying archived staged kernel, boot-test marker and actual package identities'
(cd "$partial/StagedKernel" && sha256sum --quiet -c SHA256SUMS.txt) ||
  fail 'Archived kernel differs from verified original'
grep -Fq 'BOOT-FAT16-SO-LINUX-HANDOFF-PASS' "$partial/VirtualBootEvidence/Test.log" ||
  fail 'Archived VM pass evidence did not survive copying'
for pkg in "infiltratoros-kernel-image-$version" \
           "infiltratoros-kernel-headers-$version" \
           "infiltratoros-kernel-image-$version-dbg"; do
  basename_deb=$(basename "${found[$pkg]}")
  [[ $(dpkg-deb -f "$partial/OriginalBuildOutputs/$basename_deb" Package) == "$pkg" ]] ||
    fail "Archived Debian package identity differs: $basename_deb"
done

# Independent checksum inventory of every regular file copied to the durable
# archive. The original build and VM checkums remain present as well.
(
  cd "$partial"
  find OriginalBuildOutputs StagedKernel VirtualBootEvidence BuildLogs \
    -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum \
    > SHA256SUMS-Archive.txt
  sha256sum Archive-Record.txt >> SHA256SUMS-Archive.txt
  sha256sum --quiet -c SHA256SUMS-Archive.txt
) || fail 'Complete archive checksum verification failed'

[[ ! -e "$final" && ! -L "$final" ]] ||
  fail "An archive was created concurrently at $final; refusing to overwrite"
mv -T -- "$partial" "$final" || fail "Could not finalise verified archive: $final"
trap - ERR
log "PASS: preserved binary packages, staging, VM evidence and build logs at $final"
log 'Original build files and successful VM evidence remain unchanged.'
log 'Source is also persisted separately on GitHub; this is a second copy on the same host disk, not an off-machine backup.'
