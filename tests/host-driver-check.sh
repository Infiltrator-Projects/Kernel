#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
modules="$work/modules"
sys="$work/sys"
mkdir -p "$modules" "$sys/bus/pci/devices/net/driver" \
    "$sys/bus/i2c/devices/touch/driver" "$sys/module/iwlwifi" "$sys/module/i2c_hid_acpi"
ln -s "$sys/module/iwlwifi" "$sys/bus/pci/devices/net/driver/module"
ln -s "$sys/module/i2c_hid_acpi" "$sys/bus/i2c/devices/touch/driver/module"
printf '%s\n' 'kernel/drivers/net/wireless/iwlwifi.ko.zst:' > "$modules/modules.dep"
printf '%s\n' 'kernel/drivers/hid/i2c-hid-acpi.ko' > "$modules/modules.builtin"
bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$modules" "$sys"
printf '%s\n' 'kernel/drivers/unrelated.ko:' > "$modules/modules.dep"
if bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$modules" "$sys" > "$work/missing.log" 2>&1; then
    echo 'Missing Wi-Fi module was accepted' >&2; exit 1
fi
grep -Fq 'active driver missing from native build: iwlwifi' "$work/missing.log"
rm "$modules/modules.builtin"
if bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$modules" "$sys" > /dev/null 2>&1; then
    echo 'Missing built-in index was accepted' >&2; exit 1
fi
echo 'NATIVE_HOST_DRIVER_INDEX_CHECK_PASS'
