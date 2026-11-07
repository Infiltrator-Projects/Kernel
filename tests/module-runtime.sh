#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# No live module insertion/sysctl writes. Real kmod parses synthetic ELF .ko.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
version=$(tr -d '\r\n' < "$root/VERSION")
abi="$version-infiltrator"
module_base="$sandbox/System/Kernel/Modules/InfiltratorOS-$version"
runtime="$sandbox/System/Kernel/Runtime/InfiltratorOS-$version"
provider="$sandbox/System/Kernel/Filesystems"
view="$sandbox/view"
mkdir -p "$module_base/kernel/drivers/test" "$runtime" "$provider" "$sandbox/System/Filesystems"
cp "$root/scripts/infiltrator/module-runtime.sh" "$runtime/modprobe"
chmod 0755 "$runtime/modprobe"
printf '%s\n' "$version" > "$runtime/VERSION"
cat > "$sandbox/sample.c" <<EOF_C
__attribute__((used, section(".modinfo"))) static const char a[] = "vermagic=$abi SMP preempt mod_unload";
__attribute__((used, section(".modinfo"))) static const char b[] = "alias=infiltrator:test0";
EOF_C
${CC:-cc} -c -o "$module_base/kernel/drivers/test/native_test.ko" "$sandbox/sample.c"
${CC:-cc} -c -o "$provider/native_provider.ko" "$sandbox/sample.c"
sed "s/$abi/6.12.107/" "$sandbox/sample.c" > "$sandbox/stale.c"
${CC:-cc} -c -o "$provider/stale_provider.ko" "$sandbox/stale.c"
printf 'authoritative userspace module\n' > "$sandbox/System/Filesystems/FAT16.so"
old_sha=$(sha256sum "$sandbox/System/Filesystems/FAT16.so" | cut -d ' ' -f 1)
INFILTRATOROS_MODULE_VIEW_ROOT="$view" "$runtime/modprobe" prepare > "$sandbox/out" 2>&1
[[ -s "$view/current/lib/modules/$abi/modules.dep.bin" ]]
[[ -L "$view/current/lib/modules/$abi/kernel/drivers/test/native_test.ko" ]]
[[ -L "$view/current/lib/modules/$abi/updates/infiltrator-filesystems/native_provider.ko" ]]
[[ ! -e "$view/current/lib/modules/$abi/updates/infiltrator-filesystems/stale_provider.ko" ]]
INFILTRATOROS_MODULE_VIEW_ROOT="$view" "$runtime/modprobe" resolve native_test > "$sandbox/dep"
grep -Fq 'native_test.ko' "$sandbox/dep"
INFILTRATOROS_MODULE_VIEW_ROOT="$view" "$runtime/modprobe" resolve native_provider > "$sandbox/provider"
grep -Fq 'native_provider.ko' "$sandbox/provider"
[[ $(sha256sum "$sandbox/System/Filesystems/FAT16.so" | cut -d ' ' -f 1) == "$old_sha" ]]
if INFILTRATOROS_MODULE_VIEW_ROOT="$view" "$runtime/modprobe" activate > "$sandbox/activate.log" 2>&1; then
  echo 'FAIL: foreign kernel activation unexpectedly accepted' >&2; exit 1
fi
if INFILTRATOROS_MODULE_VIEW_ROOT="$view" "$runtime/modprobe" native_test > "$sandbox/load.log" 2>&1; then
  echo 'FAIL: foreign kernel module load unexpectedly accepted' >&2; exit 1
fi
grep -Fq 'Running kernel' "$sandbox/load.log"
echo 'PASS: native .ko indexing, dependencies, ABI filtering, userspace SO isolation and foreign-kernel safeguards'
