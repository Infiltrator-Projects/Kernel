#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Synthetic verification that archival never deletes/overwrites real outputs.
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/infiltrator/preserve-milestone.sh
for tool in dpkg-deb rsync sha256sum git; do command -v "$tool" >/dev/null; done

sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
version=$(tr -d '\r\n' < VERSION)
original="$sandbox/Original"
stage="$sandbox/Staging"
evidence="$sandbox/VM"
archive_root="$sandbox/Archives"
mkdir -p "$original/native" "$stage/System/Kernel/Images" \
  "$evidence/VirtualMachine" "$sandbox/Pkg/DEBIAN"
printf '%s\n' 'Original historical data must survive' > "$original/native/Untouched.txt"
printf '%s\n' 'Compiled kernel image' > "$stage/System/Kernel/Images/InfiltratorOS-$version.img"
(cd "$stage" && find System -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS.txt)
printf '%s\n' 'BOOT-FAT16-SO-LINUX-HANDOFF-PASS' > "$evidence/Test.log"
printf '%s\n' 'Guest serial output' > "$evidence/VirtualMachine/serial.log"
printf '%s\n' 'Disposable image' > "$evidence/VirtualMachine/esp.img"
original_hash=$(sha256sum "$original/native/Untouched.txt" | cut -d' ' -f1)
for pkg in "infiltratoros-kernel-image-$version" \
           "infiltratoros-kernel-headers-$version" \
           "infiltratoros-kernel-image-$version-dbg"; do
  cat > "$sandbox/Pkg/DEBIAN/control" <<EOF
Package: $pkg
Version: $version-1
Architecture: amd64
Maintainer: InfiltratorOS Archive Test <noreply@example.invalid>
Description: Synthetic archival test package
EOF
  dpkg-deb --build "$sandbox/Pkg" "$original/${pkg}_${version}-1_amd64.deb" >/dev/null
done

bash scripts/infiltrator/preserve-milestone.sh \
  --packages "$original" --stage "$stage" --evidence "$evidence" \
  --archive-root "$archive_root"
dest="$archive_root/InfiltratorOS-Kernel-$version"
[[ -s "$dest/Archive-Record.txt" && -s "$dest/SHA256SUMS-Archive.txt" ]]
[[ -s "$dest/OriginalBuildOutputs/native/Untouched.txt" ]]
[[ -s "$dest/StagedKernel/System/Kernel/Images/InfiltratorOS-$version.img" ]]
[[ -s "$dest/VirtualBootEvidence/VirtualMachine/esp.img" ]]
[[ $(sha256sum "$original/native/Untouched.txt" | cut -d' ' -f1) == "$original_hash" ]]
grep -Fq 'BOOT-FAT16-SO-LINUX-HANDOFF-PASS' "$dest/VirtualBootEvidence/Test.log"
(cd "$dest" && sha256sum --quiet -c SHA256SUMS-Archive.txt)
(cd "$dest/StagedKernel" && sha256sum --quiet -c SHA256SUMS.txt)

# Idempotent safety: no second run may overwrite the first final archive.
if bash scripts/infiltrator/preserve-milestone.sh \
  --packages "$original" --stage "$stage" --evidence "$evidence" \
  --archive-root "$archive_root" >"$sandbox/SecondAttempt.log" 2>&1; then
  echo 'FAIL: Existing archive was overwritten' >&2
  exit 1
fi
grep -Fq 'refusing to overwrite' "$sandbox/SecondAttempt.log"
[[ $(sha256sum "$original/native/Untouched.txt" | cut -d' ' -f1) == "$original_hash" ]]
(cd "$dest" && sha256sum --quiet -c SHA256SUMS-Archive.txt)

echo 'PASS: original packages, staged kernel and VM evidence archived with verified hashes; originals preserved; overwrite refused'
