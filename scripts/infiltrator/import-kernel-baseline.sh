#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Import the exact Ubuntu HWE source snapshot as the repository-root kernel.
# This runs only on a disposable GitHub Actions runner.
set -euo pipefail
repo="${GITHUB_WORKSPACE:?Not in GitHub Actions}"
[[ -d "$repo/.git" ]] || { echo "Missing repository checkout" >&2; exit 1; }
cd "$repo"
[[ "$(git branch --show-current)" == "main" ]] || { echo "Only main is supported" >&2; exit 1; }
[[ "$(git status --porcelain)" == "" ]] || { echo "Checkout is not clean" >&2; exit 1; }
if [[ -f arch/x86/Makefile && -f kernel/sched/core.c && -f COPYING ]]; then
  echo "Full kernel source is already present; nothing to import."
  exit 0
fi

version='7.0.0-42.42~24.04.1'
package='linux-hwe-7.0'
temp="${RUNNER_TEMP:?}/kernel-official-source"
mkdir -p "$temp"
echo "Downloading exact official source: $package=$version"
(cd "$temp" && apt-get source "$package=$version")

src="$temp/linux-hwe-7.0-7.0.0"
for required in Makefile COPYING Kconfig arch/x86/Makefile kernel/sched/core.c scripts/kconfig/Makefile; do
  [[ -f "$src/$required" ]] || { echo "Missing official source file: $required" >&2; exit 1; }
done
grep -Eq '^VERSION[[:space:]]*=[[:space:]]*7$' "$src/Makefile" || { echo 'Wrong kernel major version' >&2; exit 1; }
grep -Eq '^PATCHLEVEL[[:space:]]*=[[:space:]]*0$' "$src/Makefile" || { echo 'Wrong kernel minor version' >&2; exit 1; }

# Distinct root-level kernel source. Keep the previous wrapper for provenance,
# but make the real Linux Kbuild Makefile the root Makefile from this commit onward.
mkdir -p scripts/infiltrator docs/upstream
cp Makefile scripts/infiltrator/Makefile.before-import
if [[ -f "$src/README.md" ]]; then
  cp "$src/README.md" docs/upstream/README.md
fi
echo 'Copying official source into root (retaining all copyright and licence files)'
rsync -a --exclude='/.pc/' --exclude='/.config' --exclude='/.git/' "$src/" "$repo/"

# Keep project README, which was not part of the kernel upstream tree on
# most source releases. If upstream defines README.md, preserve it separately.
cat > README.md <<'README'
# InfiltratorOS Kernel

This repository contains the **complete Ubuntu Linux HWE 7.0 kernel source**
used as the initial InfiltratorOS kernel baseline. It is maintained directly
in the repository root, not inside a subdirectory or as a download-only wrapper.

Initial source: Ubuntu linux-hwe-7.0 7.0.0-42.42~24.04.1, including the
distribution's source patch set. See [baseline provenance](docs/upstream/BASELINE.md).
The original Linux kernel COPYING and LICENSES/ notices remain applicable.

**Current status:** This is an InfiltratorOS-maintained Linux kernel baseline,
not yet an independently implemented kernel. It has not yet passed native
Mint/Debian compilation and boot qualification.

Boot is maintained in Infiltrator-Projects/Boot. Format-specific filesystem
engines remain owned by their independent Filesystem-* repositories.

## Native builder

- `make probe` checks the host and installed source configuration.
- `make configure-only` configures an out-of-tree build using Mint/Debian defaults.
- `make build-only` compiles local Debian image and header packages, without installation.
- `make check` checks the first-party build script syntax and contract (not the kernel).

The first-party scripts use APT build dependencies on Debian/Linux Mint
and need the appropriate deb-src entries. They do not change the running
kernel or boot configuration. The first-party builder is
`scripts/build-native.sh`. The Linux kernel's normal Kbuild targets
remain available.
README

cat >> Makefile <<'MAKE'

# InfiltratorOS build entry points; preserve all original Kbuild functionality.
.PHONY: probe configure-only build-only check
probe:
	@bash scripts/build-native.sh --probe
configure-only:
	@bash scripts/build-native.sh --configure-only
build-only:
	@bash scripts/build-native.sh --build-only
check:
	@bash tests/check.sh
MAKE

# Preserve upstream .gitignore and add only Infiltrator work directories.
cat >> .gitignore <<'IGNORE'

# InfiltratorOS native-build scratch and output
.native-build/
dist/
upstream/
IGNORE

cat > docs/upstream/BASELINE.md <<'BASELINE'
# Original kernel source provenance

The initial InfiltratorOS Kernel root source is the complete Ubuntu HWE
Linux source package `linux-hwe-7.0`, version
`7.0.0-42.42~24.04.1` for Ubuntu 24.04 (noble).

Source retrieved by `apt-get source linux-hwe-7.0=7.0.0-42.42~24.04.1`
using authenticated Ubuntu archive package indexes on a clean Ubuntu 24.04
GitHub Actions runner. Both the upstream source archive and the Ubuntu diff
were extracted/applied by dpkg-source. This is the same source identity as
the installed `linux-headers-7.0.0-42-generic` on the original Mint 22.3
test machine.

The original Linux kernel's licence, notices, attributions, generated ABI
documentation, Kbuild, package metadata and source directory structure
remain in the root tree. The InfiltratorOS additions are first-party builder
scripts and documentation. Retaining kernel identification, copyright
notices and ABI semantics is required for compatibility and legal accuracy.

Build-host configuration files and generated objects are not part of this
source baseline. Tests of native compilation, VM boot, hardware boot and
installer recovery remain outstanding.
BASELINE
for item in "$temp"/*.dsc "$temp"/*.orig.tar.gz "$temp"/*.diff.gz; do
  [[ -f "$item" ]] || continue
  sha256sum "$item" | sed 's@  .*/@  @' >> docs/upstream/SHA256SUMS.txt
done
# Reject large blobs rather than permitting GitHub to fail mid-upload.
large=$(find . -path './.git' -prune -o -type f -size +95M -print -quit)
[[ -z "$large" ]] || { echo "File over 95 MiB: $large" >&2; exit 1; }
git add -A
files=$(git diff --cached --name-only | wc -l)
echo "Staged $files files"
(( files > 10000 )) || { echo "Refusing incomplete kernel source import" >&2; exit 1; }
git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' commit -m "Import full official Ubuntu HWE 7.0 kernel source as InfiltratorOS baseline"
git push origin HEAD:main
echo "Full kernel source imported to main."
