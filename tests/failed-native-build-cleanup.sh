#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Run the actual generated bootstrap with disposable fake source/build tools.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/preserved"
printf 'untouched\n' > "$sandbox/preserved/marker"
awk 'index($0, "cat > \"$tmp\" <<\047RUNNER\047") == 1 { copy=1; next }
     copy && $0 == "RUNNER" { exit } copy { print }' \
  "$root/scripts/infiltrator/package-run.sh" > "$sandbox/runner"
[[ -s "$sandbox/runner" ]]
sed -i 's/__PINNED_COMMIT__/0000000000000000000000000000000000000000/' "$sandbox/runner"
cat > "$sandbox/bin/git" <<'FAKEGIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == init ]]; then
  mkdir -p "${@: -1}/scripts/infiltrator"
elif [[ $1 == -C ]]; then
  source=$2
  case "$3" in
    rev-parse) printf '%040d\n' 0 ;;
    fetch)
      printf '# fake kernel\n' > "$source/Makefile"
      printf '0.1.9\n' > "$source/VERSION"
      cat > "$source/scripts/build-native.sh" <<'BUILD'
#!/usr/bin/env bash
set -euo pipefail
while (( $# )); do
  case $1 in
    --object-dir) shift; object_path=$1; mkdir -p "$1"; printf 'object\n' > "$1/marker" ;;
    --packages-dir) shift; mkdir -p "$1"; printf 'package\n' > "$1/marker" ;;
  esac
  shift
done
if [[ ${FAKE_REPLACE_WORKSPACE:-0} == 1 ]]; then
  original=${object_path%/obj}
  mv -- "$original" "$original.saved"
  mkdir -- "$original"
  printf 'other data\n' > "$original/marker"
  exit 42
fi
[[ ${FAKE_BUILD_FAIL:-0} != 1 ]]
BUILD
      cat > "$source/scripts/infiltrator/stage-native.sh" <<'STAGE'
#!/usr/bin/env bash
set -euo pipefail
while (( $# )); do
  if [[ $1 == --output ]]; then shift; out=$1; fi
  shift
done
mkdir -p "$out"
printf 'stage\n' > "$out/marker"
( cd "$out" && sha256sum marker > SHA256SUMS.txt )
STAGE
      printf '#!/bin/sh\nexit 0\n' > "$source/scripts/infiltrator/install-native.sh"
      ;;
  esac
fi
FAKEGIT
chmod +x "$sandbox/bin/git"
# The bootstrap checks rsync availability even for --build-only.
printf '#!/bin/sh\nexit 0\n' > "$sandbox/bin/rsync"
chmod +x "$sandbox/bin/rsync"
export PATH="$sandbox/bin:$PATH" INFILTRATOROS_TEMP_ROOT="$sandbox/temp"
if FAKE_BUILD_FAIL=1 bash "$sandbox/runner" --build-only > "$sandbox/failure.log" 2>&1; then
  echo 'Failed build returned success' >&2; exit 1
fi
shopt -s nullglob
builds=("$sandbox"/temp/Kernel/Build/InfiltratorOS-Run.*)
logs=("$sandbox"/temp/Kernel/Logs/InfiltratorOS-Run.*.log)
packages=("$sandbox"/temp/Kernel/Packages/InfiltratorOS-Run.*/marker)
[[ ${#builds[@]} == 0 && ${#logs[@]} == 1 && ${#packages[@]} == 1 ]]
grep -Fq 'Removed failed temporary build:' "$sandbox/failure.log"
[[ $(<"$sandbox/preserved/marker") == untouched ]]
FAKE_BUILD_FAIL=0 bash "$sandbox/runner" --build-only > "$sandbox/success.log" 2>&1
builds=("$sandbox"/temp/Kernel/Build/InfiltratorOS-Run.*/obj/marker)
[[ ${#builds[@]} == 1 && $(<"${builds[0]}") == object ]]
if FAKE_REPLACE_WORKSPACE=1 bash "$sandbox/runner" --build-only > "$sandbox/replaced.log" 2>&1; then
  echo 'Replaced workspace returned success' >&2; exit 1
fi
grep -Fq 'build workspace changed; no automatic cleanup' "$sandbox/replaced.log"
markers=("$sandbox"/temp/Kernel/Build/InfiltratorOS-Run.*/marker)
[[ ${#markers[@]} == 1 && $(<"${markers[0]}") == 'other data' ]]
echo 'FAILED_NATIVE_BUILD_CLEANUP_PASS'
