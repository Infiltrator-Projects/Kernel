#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Publishable source-bearing InfiltratorOS Kernel .run installer.
# Embeds GitHub-committed source, never local compiler objects.
set -euo pipefail
fail() { printf 'InfiltratorOS Kernel release: ERROR: %s\n' "$*" >&2; exit 1; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root"
for tool in git xz tar sha256sum; do
  command -v "$tool" >/dev/null || fail "Missing utility: $tool"
done
[[ -d .git ]] || fail 'Release bundle must be created from a Git checkout'
[[ -z $(git status --porcelain --untracked-files=no) ]] ||
  fail 'Tracked source modifications must be committed before packaging'
version=$(tr -d '\r\n' < VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid Kernel VERSION'
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] ||
  fail 'Invalid temporary root'
out="$temporary_root/Kernel/Packages"
mkdir -p "$out" || fail "Cannot create native package destination: $out"
outfile="$out/InfiltratorOS-Kernel-$version-amd64.run"
[[ ! -e "$outfile" && ! -L "$outfile" ]] ||
  fail "Existing source-bearing release preserved: $outfile"
tmp=$(mktemp "$out/.InfiltratorOS-Kernel-$version.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT
cat > "$tmp" <<'RUNNER'
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# InfiltratorOS Kernel: from GitHub-committed source, compile a truly fresh
# independent object tree, check actual .debs, and install to /System/Kernel.
# Never installs under Mint's /boot, /lib/modules or /usr; never edits EFI.
set -euo pipefail
fail() { printf 'InfiltratorOS Kernel .run: ERROR: %s\n' "$*" >&2; exit 1; }
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo 'Usage: ./InfiltratorOS-Kernel-0.1.0-amd64.run [--build-only] [--jobs N] [--install-deps]'
  echo 'Default: extract fresh GitHub source under /Temporary/InfiltratorOS/Kernel,'
  echo 'compile actual Kernel and modules (never reuse old objects), validate .deb'
  echo 'installation paths and install only under /System/Kernel.'
  echo 'Boot activation and EFI/NVRAM changes are NOT performed.'
  echo '--build-only: compile/test without installing under /System/Kernel.'
  echo '--install-deps: explicitly permit APT to install build prerequisites.'
  exit 0
fi
build_only=0
install_deps=0
jobs=
while (( $# )); do
  case "$1" in
    --build-only) build_only=1 ;;
    --install-deps) install_deps=1 ;;
    --jobs)
      shift; (( $# )) || fail '--jobs requires a number'
      [[ "$1" =~ ^[1-9][0-9]*$ ]] || fail 'Invalid job count'
      jobs=$1 ;;
    *) fail "Unexpected option: $1" ;;
  esac
  shift
done
for tool in tar xz mktemp tee dpkg-deb sha256sum rsync; do
  command -v "$tool" >/dev/null || fail "Missing utility: $tool"
done
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] ||
  fail 'Invalid /Temporary workspace'
workspace="$temporary_root/Kernel"
mkdir -p "$workspace/Build" "$workspace/Logs" "$workspace/Packages" "$workspace/Staging" ||
  fail "Cannot create /Temporary workspace: $workspace"
work=$(mktemp -d "$workspace/Build/InfiltratorOS-Run.XXXXXXXX")
source_dir="$work/Source"
obj="$work/obj"
run_name=${work##*/}
packages="$workspace/Packages/$run_name"
stage="$workspace/Staging/$run_name"
logfile="$workspace/Logs/$run_name.log"
mkdir -p "$source_dir"
line=$(awk '/^__INFILTRATOR_KERNEL_SOURCE_ARCHIVE_BELOW__$/ { print NR + 1; exit }' "$0")
[[ "$line" =~ ^[1-9][0-9]*$ ]] || fail 'Missing embedded GitHub source archive'
tail -n "+$line" "$0" | xz -dc | tar -xf - -C "$source_dir" ||
  fail 'Embedded source extraction failed'
[[ -s "$source_dir/Makefile" && -s "$source_dir/VERSION" &&
   -s "$source_dir/scripts/build-native.sh" &&
   -s "$source_dir/scripts/infiltrator/install-native.sh" ]] ||
  fail 'Embedded full source does not contain the native Kernel installer'
product_version=$(tr -d '\r\n' < "$source_dir/VERSION")
printf 'InfiltratorOS Kernel: compiling new source-only build %s\n' "$product_version"
printf 'Source: %s\nObject tree: %s\nPackages: %s\n' "$source_dir" "$obj" "$packages"
printf 'Build log: %s\n' "$logfile"
args=(--build-only --fresh-objects --source-dir "$source_dir"
      --object-dir "$obj" --packages-dir "$packages")
if (( ! install_deps )); then args+=(--skip-deps); fi
if [[ -n "$jobs" ]]; then args+=(--jobs "$jobs"); fi
# Pipefail preserves true compiler failure. Logs are never discarded.
( cd "$source_dir" && bash scripts/build-native.sh "${args[@]}" ) 2>&1 | tee "$logfile" ||
  fail "Fresh compiler or native Debian packaging failed; log: $logfile"
( cd "$source_dir" && bash scripts/infiltrator/stage-native.sh \
  --packages "$packages" --objects "$obj" --output "$stage" ) 2>&1 | tee -a "$logfile" ||
  fail "Fresh native staging failed; log: $logfile"
(
  cd "$stage"
  sha256sum --quiet -c SHA256SUMS.txt
) || fail 'Fresh compiled image/modules SHA-256 verification failed'
if (( ! build_only )); then
  ( cd "$source_dir" && bash scripts/infiltrator/install-native.sh \
    --packages "$packages" ) 2>&1 | tee -a "$logfile" ||
    fail "Native /System/Kernel installation failed; log: $logfile"
  printf 'InfiltratorOS Kernel: freshly compiled and INSTALLED under /System/Kernel\n'
else
  printf 'InfiltratorOS Kernel: freshly compiled and verified; build-only requested, NOT installed\n'
fi
printf 'Source, build objects, package files, staging and log remain under %s\n' "$workspace"
printf '%s\n' 'Mint boot files, current running kernel, EFI and NVRAM were not changed.'
exit 0
__INFILTRATOR_KERNEL_SOURCE_ARCHIVE_BELOW__
RUNNER
# Signed Git tags/commit history identify provenance; the raw bundled sources
# are literally git archive HEAD, not developer-specific ~/Kernel changes.
git archive --format=tar HEAD | xz -T2 -6 >> "$tmp" ||
  fail 'Could not create compressed GitHub source archive'
chmod 755 "$tmp"
mv -- "$tmp" "$outfile"
trap - EXIT
printf 'InfiltratorOS Kernel release: source-bearing installer created: %s\n' "$outfile"
printf '%s\n' 'The .run compiles fresh in /Temporary and installs only under /System/Kernel.'
