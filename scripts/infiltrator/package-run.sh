#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Publish a SMALL network-bootstrap .run. Kernel source stays in public Git.
# The host executing this .run downloads the exact committed source and builds.
set -euo pipefail
fail() { printf 'InfiltratorOS Kernel release: ERROR: %s\n' "$*" >&2; exit 1; }
root=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$root"
command -v git >/dev/null || fail 'git is required to identify the release commit'
[[ -d .git ]] || fail 'Produce public releases from a checked-out repository'
[[ -z $(git status --porcelain --untracked-files=no) ]] ||
  fail 'Commit tracked changes to GitHub before packaging'
version=$(tr -d '\r\n' < VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid Kernel VERSION'
commit=$(git rev-parse HEAD)
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || fail 'Could not pin the exact public source commit'
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] || fail 'Invalid Temporary root'
out="$temporary_root/Kernel/Packages"
mkdir -p "$out" || fail 'Cannot create package output directory'
outfile="$out/InfiltratorOS-Kernel-$version-amd64.run"
[[ ! -e "$outfile" && ! -L "$outfile" ]] ||
  fail "Existing .run preserved: $outfile"
tmp=$(mktemp "$out/.InfiltratorOS-Kernel-$version.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT
cat > "$tmp" <<'RUNNER'
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Small public bootstrap installer. The kernel source is DOWNLOADED from
# Infiltrator-Projects/Kernel at the release's exact pinned Git commit.
# All source, compiler objects, packages and logs live under /Temporary.
set -euo pipefail
fail() { printf 'InfiltratorOS Kernel .run: ERROR: %s\n' "$*" >&2; exit 1; }
repo='https://github.com/Infiltrator-Projects/Kernel.git'
expected_commit=__PINNED_COMMIT__
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  printf 'Usage: %s [--build-only] [--jobs N] [--install-deps] [--replace-existing] [--trial-infiltratorfs]\n' "$0"
  echo 'Downloads the exact release source from GitHub into /Temporary/InfiltratorOS/Kernel.'
  echo 'Freshly compiles on THIS machine, verifies actual native Debian package paths,'
  echo 'and installs files under /System/Kernel (not under Mint /boot).'
  echo 'Does not change EFI/NVRAM or activate a new boot kernel.'
  echo '--build-only: download, compile and verify without native file installation.'
  echo '--install-deps: allow APT installation of missing build prerequisites.'
  echo '--replace-existing: archive and replace previously installed same-version native Kernel files.'
  echo '--trial-infiltratorfs: run isolated Boot -> InfiltratorFS -> real Kernel -> native filesystem mount/read/write QEMU qualification.'
  echo 'Trial needs QEMU, OVMF, gnu-efi, mtools, dosfstools, busybox-static, zstd and filesystem build dependencies.'
  exit 0
fi
build_only=0
install_deps=0
replace_existing=0
trial_infiltratorfs=0
jobs=
while (( $# )); do
  case "$1" in
    --build-only) build_only=1 ;;
    --install-deps) install_deps=1 ;;
    --replace-existing) replace_existing=1 ;;
    --trial-infiltratorfs) trial_infiltratorfs=1 ;;
    --jobs)
      shift; (( $# )) || fail '--jobs requires a number'
      [[ "$1" =~ ^[1-9][0-9]*$ ]] || fail 'Invalid --jobs value'
      jobs=$1 ;;
    *) fail "Unknown option: $1" ;;
  esac
  shift
done
if (( build_only && replace_existing )); then
  fail '--replace-existing requires native installation, not --build-only'
fi
for tool in git mktemp tee dpkg-deb sha256sum rsync; do
  command -v "$tool" >/dev/null || fail "Required command not installed: $tool"
done
temporary_root=${INFILTRATOROS_TEMP_ROOT:-/Temporary/InfiltratorOS}
[[ "$temporary_root" == /* && "$temporary_root" != / ]] || fail 'Invalid Temporary root'
workspace="$temporary_root/Kernel"
# Bootstrap a completely clean machine. A normal user cannot create the
# system-owned top-level /Temporary namespace without elevation. Obtain
# elevation ONLY if directories are absent; never chown or reset an existing
# directory, and never create a home-directory build tree.
if [[ "$temporary_root" == /Temporary/InfiltratorOS ]]; then
  for parent in /Temporary /Temporary/InfiltratorOS; do
    if [[ -L "$parent" ]]; then
      fail "Refusing symlinked system Temporary path: $parent"
    fi
    if [[ -e "$parent" && ! -d "$parent" ]]; then
      fail "System Temporary path exists but is not a directory: $parent"
    fi
    if [[ ! -d "$parent" ]]; then
      printf 'Creating missing system directory %s\n' "$parent"
      if (( EUID == 0 )); then
        install -d -m 0755 -- "$parent"
      else
        command -v sudo >/dev/null ||
          fail "sudo is needed once to create missing system directory $parent"
        sudo install -d -m 0755 -- "$parent" ||
          fail "Could not create missing system directory $parent"
      fi
    fi
  done
  if [[ -L "$workspace" ]]; then
    fail "Refusing symlinked Kernel workspace: $workspace"
  fi
  if [[ -e "$workspace" && ! -d "$workspace" ]]; then
    fail "Kernel workspace exists but is not a directory: $workspace"
  fi
  if [[ ! -d "$workspace" ]]; then
    printf 'Creating missing Kernel workspace %s\n' "$workspace"
    if (( EUID == 0 )); then
      install -d -m 0755 -- "$workspace"
    else
      sudo install -d -m 0755 -o "$(id -un)" -g "$(id -gn)" -- "$workspace" ||
        fail "Could not create user-owned Kernel workspace $workspace"
    fi
  fi
else
  # Explicit custom Temporary root remains caller-owned. Do not sudo or
  # change ownership of user-supplied external directories.
  [[ ! -L "$temporary_root" && ! -L "$workspace" ]] ||
    fail 'Refusing symlinked custom Temporary root/workspace'
  mkdir -p -- "$workspace" ||
    fail "Cannot create custom Temporary workspace: $workspace"
fi
[[ -w "$workspace" && -x "$workspace" ]] ||
  fail "Native Kernel workspace is not writable by this user: $workspace"
mkdir -p "$workspace/Build" "$workspace/Logs" "$workspace/Packages" "$workspace/Staging" ||
  fail "Cannot create native Temporary build directories: $workspace"
work=$(mktemp -d "$workspace/Build/InfiltratorOS-Run.XXXXXXXX")
source_dir="$work/Source"
obj="$work/obj"
run_name=${work##*/}
packages="$workspace/Packages/$run_name"
stage="$workspace/Staging/$run_name"
logfile="$workspace/Logs/$run_name.log"
printf 'Downloading InfiltratorOS Kernel source from GitHub commit %s\n' "$expected_commit"
# Pin the immutable revision embedded at publication; NEVER silently switch
# to a later main commit or use another machine's private compiler objects.
git init -q -b main "$source_dir" || fail 'Cannot initialise source workspace'
git -C "$source_dir" remote add origin "$repo"
git -C "$source_dir" fetch --no-tags --depth 1 origin "$expected_commit" ||
  fail 'Cannot fetch exact released source from public GitHub'
git -C "$source_dir" checkout --detach -q FETCH_HEAD ||
  fail 'Cannot check out verified public source commit'
[[ $(git -C "$source_dir" rev-parse HEAD) == "$expected_commit" ]] ||
  fail 'Downloaded source is not the committed release revision'
[[ -s "$source_dir/Makefile" && -s "$source_dir/VERSION" &&
   -s "$source_dir/scripts/build-native.sh" &&
   -s "$source_dir/scripts/infiltrator/install-native.sh" ]] ||
  fail 'Downloaded GitHub revision is incomplete'
product_version=$(tr -d '\r\n' < "$source_dir/VERSION")
printf 'Building InfiltratorOS Kernel %s, fresh on this computer\n' "$product_version"
printf 'Source: %s\nObjects: %s\nPackages: %s\nLog: %s\n' \
  "$source_dir" "$obj" "$packages" "$logfile"
args=(--build-only --fresh-objects --source-dir "$source_dir"
      --object-dir "$obj" --packages-dir "$packages")
if (( ! install_deps )); then args+=(--skip-deps); fi
if [[ -n "$jobs" ]]; then args+=(--jobs "$jobs"); fi
( cd "$source_dir" && bash scripts/build-native.sh "${args[@]}" ) 2>&1 | tee "$logfile" ||
  fail "Fresh source compiler or package generation failed; see $logfile"
( cd "$source_dir" && bash scripts/infiltrator/stage-native.sh \
  --packages "$packages" --objects "$obj" --output "$stage" ) 2>&1 | tee -a "$logfile" ||
  fail "Native staging failed; see $logfile"
( cd "$stage" && sha256sum --quiet -c SHA256SUMS.txt ) ||
  fail "Native staged output checksum failure; see $logfile"
if (( trial_infiltratorfs )); then
  mkdir -p "$workspace/Tests" ||
    fail 'Cannot create isolated three-way trial evidence directory'
  printf 'Running actual Boot -> InfiltratorFS -> InfiltratorOS Kernel trial in QEMU\n'
  trial_args=(--source "$source_dir" --objects "$obj" --stage "$stage" --workspace "$workspace/Tests")
  if [[ -n "$jobs" ]]; then trial_args+=(--jobs "$jobs"); fi
  if (( install_deps )); then trial_args+=(--install-deps); fi
  ( cd "$source_dir" && bash scripts/infiltrator/test-infiltratorfs-boot.sh
    "${trial_args[@]}" ) 2>&1 | tee -a "$logfile" ||
    fail "Three-project QEMU trial failed; see logs under $workspace/Tests"
fi
if (( ! build_only )); then
  install_args=(--packages "$packages")
  if (( replace_existing )); then
    install_args+=(--replace-existing)
  elif [[ -e "/System/Kernel/Images/InfiltratorOS-$product_version.img" ||
          -e "/System/Kernel/Runtime/InfiltratorOS-$product_version" ]]; then
    # The public .run is a self-contained upgrade path. An older native
    # kernel of the same component version must not make a second run fail.
    # The native installer backs up every replaced versioned path first.
    printf "Existing native Kernel %s found; preserving and upgrading it.\n" "$product_version"
    install_args+=(--replace-existing)
  fi
  ( cd "$source_dir" && bash scripts/infiltrator/install-native.sh \
    "${install_args[@]}" ) 2>&1 | tee -a "$logfile" ||
    fail "Native installation failed; see $logfile"
  printf 'PASS: locally compiled Kernel installed to /System/Kernel\n'
else
  printf 'PASS: locally compiled Kernel and native packages verified; not installed\n'
fi
printf 'Build outputs and log retained under %s\n' "$workspace"
printf '%s\n' 'No changes to existing Mint boot files, EFI or NVRAM.'
RUNNER
sed -i "s/^expected_commit=__PINNED_COMMIT__$/expected_commit=$commit/" "$tmp"
grep -Fxq "expected_commit=$commit" "$tmp" || fail 'Bootstrap source commit pin missing'
if grep -Fq '__INFILTRATOR_KERNEL_SOURCE_ARCHIVE_BELOW__' "$tmp"; then
  fail 'Source archive marker must not be inside lightweight installer'
fi
chmod 755 "$tmp"
mv -- "$tmp" "$outfile"
# A second, equally lightweight asset is deliberately a TEST, never an install.
# Clicking this .run starts the full image-only three-way QEMU qualification
# with all flags preselected. The normal product .run is unchanged.
trialfile="$out/InfiltratorOS-Kernel-$version-InfiltratorFS-Trial-amd64.run"
[[ ! -e "$trialfile" && ! -L "$trialfile" ]] ||
  fail "Existing trial .run preserved: $trialfile"
trialtmp=$(mktemp "$out/.InfiltratorFS-Trial-$version.XXXXXXXX")
trap 'rm -f -- "$trialtmp"' EXIT
cp -- "$outfile" "$trialtmp"
sed -i \
  -e 's/^build_only=0$/build_only=1/' \
  -e 's/^install_deps=0$/install_deps=1/' \
  -e 's/^trial_infiltratorfs=0$/trial_infiltratorfs=1/' \
  "$trialtmp"
grep -Fxq 'build_only=1' "$trialtmp" ||
  fail 'Trial launcher must not install or activate host kernel'
grep -Fxq 'install_deps=1' "$trialtmp" ||
  fail 'Trial launcher must include its QEMU/EFI dependencies'
grep -Fxq 'trial_infiltratorfs=1' "$trialtmp" ||
  fail 'Trial launcher must start InfiltratorFS boot test automatically'
grep -Fxq "expected_commit=$commit" "$trialtmp" ||
  fail 'Trial launcher source revision is not pinned'
chmod 755 "$trialtmp"
mv -- "$trialtmp" "$trialfile"
trap - EXIT
printf 'InfiltratorOS Kernel release: native installer .run: %s\n' "$outfile"
printf 'InfiltratorOS Kernel release: isolated three-way trial .run: %s\n' "$trialfile"
printf 'Both download source pinned to commit %s\n' "$commit"
