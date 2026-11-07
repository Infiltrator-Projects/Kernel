#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Source-bearing .run bundle. All uninstalled outputs live in /Temporary,
# and permanent /System/Kernel is reserved for the qualified OS installer.
set -euo pipefail
fail() { printf 'InfiltratorOS Kernel .run: ERROR: %s\n' "$*" >&2; exit 1; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root"
command -v git >/dev/null && command -v xz >/dev/null || fail 'git and xz required'
[[ -d .git ]] || fail 'Source bundle must be generated from a Git checkout'
[[ -z $(git status --porcelain --untracked-files=no) ]] ||
  fail 'Tracked files changed; commit before packaging'
version=$(tr -d '\r\n' < VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.+][a-zA-Z0-9.-]+)?$ ]] ||
  fail 'Invalid VERSION'
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] ||
  fail "Invalid native Temporary root: $temporary_root"
out="$temporary_root/Kernel/Packages"
mkdir -p "$out" || fail "Cannot write native Temporary packages directory: $out"
outfile="$out/InfiltratorOS-Kernel-$version-amd64.run"
[[ ! -e "$outfile" && ! -L "$outfile" ]] ||
  fail "Existing source-bearing bundle preserved: $outfile"
tmp=$(mktemp "$out/.InfiltratorOS-Kernel-XXXXXXXX") || fail 'Cannot allocate temporary bundle'
trap 'rm -f -- "$tmp"' EXIT
cat > "$tmp" <<'RUNNER'
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# InfiltratorOS Kernel: compile and stage into /Temporary, never /System.
set -euo pipefail
fail() { printf 'InfiltratorOS Kernel: ERROR: %s\n' "$*" >&2; exit 1; }
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo 'Usage: InfiltratorOS-Kernel-<version>-amd64.run [--skip-deps] [--jobs N]'
  echo 'Builds on this Mint/Debian machine in /Temporary/InfiltratorOS/Kernel.'
  echo 'Does not install or boot a kernel.'
  exit 0
fi
args=(--build-only)
while (( $# )); do
  case "$1" in
    --skip-deps) args+=(--skip-deps) ;;
    --jobs) shift; (( $# )) || fail 'Missing job count'; args+=(--jobs "$1") ;;
    *) fail "Unsupported option: $1" ;;
  esac
  shift
done
command -v tar >/dev/null && command -v xz >/dev/null ||
  fail 'tar and xz required'
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] ||
  fail "Invalid native Temporary root: $temporary_root"
native_workspace="$temporary_root/Kernel"
mkdir -p "$native_workspace/Build" "$native_workspace/Logs" ||
  fail "Cannot write native Temporary workspace: $native_workspace"
work=$(mktemp -d "$native_workspace/Build/InfiltratorOS-Run.XXXXXXXX") ||
  fail 'Could not allocate build workspace'
# Preserve this extracted source and its compilation objects even if a build
# fails. They can be inspected or resumed without downloading the source.
mkdir -p "$work/Source"
line=$(awk '/^__INFILTRATOR_KERNEL_SOURCE_ARCHIVE_BELOW__$/ { print NR + 1; exit }' "$0")
[[ "$line" =~ ^[0-9]+$ ]] || fail 'Missing embedded source archive'
tail -n "+$line" "$0" | xz -dc | tar -xf - -C "$work/Source"
[[ -f "$work/Source/Makefile" && -f "$work/Source/scripts/build-native.sh" ]] ||
  fail 'Source archive incomplete'
logfile="$native_workspace/Logs/InfiltratorOS-Kernel-build.log"
[[ ! -e "$logfile" ]] || fail "Existing log preserved: $logfile"
printf 'InfiltratorOS Kernel: compiling source; log: %s\n' "$logfile"
printf 'InfiltratorOS Kernel: source and objects retained at: %s\n' "$work/Source"
( cd "$work/Source" && bash scripts/build-native.sh "${args[@]}" ) 2>&1 | tee "$logfile"
( cd "$work/Source" && bash scripts/infiltrator/stage-native.sh ) 2>&1 | tee -a "$logfile"
printf 'InfiltratorOS Kernel: packages: %s\n' "$native_workspace/Packages"
printf 'InfiltratorOS Kernel: uninstalled native staging: %s\n' "$native_workspace/Staging"
printf '%s\n' 'Not installed: the host /System/Kernel, bootloader and running kernel were unchanged.'
exit 0
__INFILTRATOR_KERNEL_SOURCE_ARCHIVE_BELOW__
RUNNER
# Archive original source plus licences; do not smuggle local compiled objects
# or historical dist/ directories into the release builder.
git archive --format=tar HEAD | xz -T2 -6 >> "$tmp"
chmod 755 "$tmp"
mv -- "$tmp" "$outfile"
trap - EXIT
printf 'InfiltratorOS Kernel .run: source-bearing builder: %s\n' "$outfile"
printf '%s\n' 'This is an uninstalled package staged in Temporary; permanent installation is not performed.'
