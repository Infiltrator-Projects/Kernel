#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Produce a source-bearing self-extracting .run native kernel builder.
# It builds on the target host and stages artifacts; no host installation.
set -euo pipefail
fail() { echo "Kernel .run: ERROR: $*" >&2; exit 1; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root"
command -v git >/dev/null && command -v xz >/dev/null || fail 'git and xz required'
[[ -d .git ]] || fail 'Source bundle must be generated from a Git checkout'
[[ -z $(git status --porcelain --untracked-files=no) ]] || fail 'Tracked files changed; commit them before packaging'
version=$(tr -d '\r\n' < VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.+][a-zA-Z0-9.-]+)?$ ]] || fail 'Invalid VERSION'
mkdir -p dist
outfile="$root/dist/InfiltratorOS-Kernel-$version-amd64.run"
[[ ! -L "$outfile" ]] || fail 'Refusing symlink output'
tmp=$(mktemp "$root/dist/.kernel-run.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT
cat > "$tmp" <<'RUNNER'
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# InfiltratorOS Kernel self-extracting source build.
# Does not install a kernel or rewrite the existing boot configuration.
set -euo pipefail
fail() { echo "InfiltratorOS Kernel: ERROR: $*" >&2; exit 1; }
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo 'Usage: InfiltratorOS-Kernel-<version>-amd64.run [--skip-deps] [--jobs N]'
  echo 'Builds for this Mint/Debian machine and stages under InfiltratorOS-Kernel-Artifacts/'
  echo 'Does not install or select the compiled kernel.'
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
command -v tar >/dev/null && command -v xz >/dev/null || fail 'tar and xz required'
start=$(pwd -P)
work=$(mktemp -d "$start/.infiltrator-kernel-build.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/source"
line=$(awk '/^__INFILTRATOR_KERNEL_SOURCE_ARCHIVE_BELOW__$/ { print NR + 1; exit }' "$0")
[[ "$line" =~ ^[0-9]+$ ]] || fail 'Missing embedded source archive'
tail -n "+$line" "$0" | xz -dc | tar -xf - -C "$work/source"
[[ -f "$work/source/Makefile" && -f "$work/source/scripts/build-native.sh" ]] || fail 'Source archive incomplete'
logfile="$start/InfiltratorOS-Kernel-build.log"
printf 'InfiltratorOS Kernel: compiling local source; log: %s\n' "$logfile"
( cd "$work/source" && bash scripts/build-native.sh "${args[@]}" ) 2>&1 | tee "$logfile"
( cd "$work/source" && bash scripts/infiltrator/stage-native.sh ) 2>&1 | tee -a "$logfile"
result="$start/InfiltratorOS-Kernel-Artifacts"
[[ ! -e "$result" && ! -L "$result" ]] || fail "Output already exists: $result (move it first)"
mv -- "$work/source/dist" "$result"
printf 'InfiltratorOS Kernel: compiled packages and native /System/Kernel tree: %s\n' "$result"
printf '%s\n' 'Not installed: this runner does not change the running kernel or boot configuration.'
exit 0
__INFILTRATOR_KERNEL_SOURCE_ARCHIVE_BELOW__
RUNNER
# git archive includes the complete tracked kernel source and licence notices,
# without untracked host .config, build objects or Git metadata.
git archive --format=tar HEAD | xz -T2 -6 >> "$tmp"
chmod 755 "$tmp"
mv -f -- "$tmp" "$outfile"
trap - EXIT
echo "Kernel .run: source-bearing native builder created: $outfile"
echo 'Kernel .run: not automatically published or installed; boot integration still unqualified.'
