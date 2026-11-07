#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Check read-only home audit and opt-in relocation using synthetic .deb files.
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/infiltrator/audit-home-artifacts.sh
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
home="$sandbox/Home"
temporary="$sandbox/Temporary/InfiltratorOS"
version=$(tr -d '\r\n' < VERSION)
release=7.0.14-infiltrator
mkdir -p "$home/InfiltratorOS-Kernel-Archive/InfiltratorOS-Kernel-$version" \
  "$temporary/Kernel/Staging/InfiltratorOS-$version" "$sandbox/pkg/DEBIAN"
printf 'build archive\n' > "$home/InfiltratorOS-Kernel-Archive/InfiltratorOS-Kernel-$version/SHA256SUMS-Archive.txt"
printf 'kernel_release=%s\n' "$release" > "$temporary/Kernel/Staging/InfiltratorOS-$version/STAGING-STATUS.txt"
printf 'Unrelated personal file\n' > "$home/Personal.txt"
printf 'Source: infiltratoros-kernel\n' > "$home/infiltratoros-kernel_${version}-1_amd64.changes"
for pkg in "infiltratoros-kernel-image-$version" "infiltratoros-kernel-image-$version-dbg" "infiltratoros-kernel-headers-$version" "linux-image-$release"; do
  cat > "$sandbox/pkg/DEBIAN/control" <<EOF
Package: $pkg
Version: 0.1.0-1
Architecture: amd64
Maintainer: InfiltratorOS Test <noreply@example.invalid>
Description: Synthetic historical home Kbuild output
EOF
  dpkg-deb --build "$sandbox/pkg" "$home/${pkg}_0.1.0-1_amd64.deb" >/dev/null
done
# Deliberately unrelated linux-deb must not be moved.
cat > "$sandbox/pkg/DEBIAN/control" <<EOF
Package: linux-image-another-project
Version: 1.0.0
Architecture: amd64
Maintainer: Another Project <noreply@example.invalid>
Description: Not this kernel build
EOF
dpkg-deb --build "$sandbox/pkg" "$home/linux-image-another-project_1.0.0_amd64.deb" >/dev/null
before=$(find "$home" -maxdepth 1 -type f -printf '%f\n' | sort)
HOME="$home" INFILTRATOROS_TEMP_ROOT="$temporary" bash scripts/infiltrator/audit-home-artifacts.sh > "$sandbox/Preview.log" 2>&1
after=$(find "$home" -maxdepth 1 -type f -printf '%f\n' | sort)
[[ "$before" == "$after" ]]
grep -Fq 'APPROVED' "$sandbox/Preview.log"
grep -Fq 'UNCLASSIFIED' "$sandbox/Preview.log"
HOME="$home" INFILTRATOROS_TEMP_ROOT="$temporary" bash scripts/infiltrator/audit-home-artifacts.sh --relocate > "$sandbox/Moved.log" 2>&1
dest="$home/InfiltratorOS-Kernel-Archive/HistoricalHomeOutputs-$version"
[[ -s "$home/Personal.txt" && -s "$home/linux-image-another-project_1.0.0_amd64.deb" ]]
[[ -s "$dest/infiltratoros-kernel-image-${version}_0.1.0-1_amd64.deb" ]]
[[ -s "$dest/linux-image-${release}_0.1.0-1_amd64.deb" ]]
[[ -s "$dest/infiltratoros-kernel_${version}-1_amd64.changes" ]]
[[ -s "$home/InfiltratorOS-Kernel-Archive/InfiltratorOS-Kernel-$version/SHA256SUMS-Archive.txt" ]]
( cd "$dest" && sha256sum --quiet -c SHA256SUMS.txt )
grep -Fq 'PASS:' "$sandbox/Moved.log"
echo 'PASS: read-only preview; strict verified home cleanup; unrelated files and complete kernel archive preserved'
