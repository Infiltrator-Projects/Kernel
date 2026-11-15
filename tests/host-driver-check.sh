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
# The user's working Mint system reports these wireless, audio, I2C controller
# and Ethernet modules. The fixture only checks indices, not device operation.
for driver in snd_hda_intel intel_lpss_pci e1000e; do
    mkdir -p "$sys/module/$driver" "$sys/bus/pci/devices/$driver/driver"
    ln -s "$sys/module/$driver" "$sys/bus/pci/devices/$driver/driver/module"
done
mkdir -p "$modules/kernel/drivers/net/wireless" "$modules/kernel/drivers/test"
printf '%s\n' 'kernel/drivers/net/wireless/iwlwifi.ko.zst:' > "$modules/modules.dep"
: > "$modules/kernel/drivers/net/wireless/iwlwifi.ko.zst"
for driver in snd_hda_intel intel_lpss_pci e1000e; do
    printf 'kernel/drivers/test/%s.ko:\n' "$driver" >> "$modules/modules.dep"
    : > "$modules/kernel/drivers/test/$driver.ko"
done
printf '%s\n' 'kernel/drivers/hid/i2c-hid-acpi.ko' > "$modules/modules.builtin"
bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$modules" "$sys"
# A built-in PCIe port driver can be linked without a modules.builtin entry.
# Use the same versioned layout, config and map format as the native package.
native="$work/native/System/Kernel"
mkdir -p "$native/Modules" "$native/Images" "$sys/module/pcieportdrv" "$sys/bus/pci/devices/port/driver"
cp -a "$modules" "$native/Modules/InfiltratorOS-0.1.9"
ln -s "$sys/module/pcieportdrv" "$sys/bus/pci/devices/port/driver/module"
printf '%s\n' 'CONFIG_PCIEPORTBUS=y' > "$native/Images/InfiltratorOS-0.1.9.config"
printf '%s\n' 'ffffffff83b47780 t pcie_portdriver' \
    'ffffffff83ff51d8 d __initcall__kmod_pcieportdrv__478_849_pcie_portdrv_init6' \
    > "$native/Images/InfiltratorOS-0.1.9.map"
bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$native/Modules/InfiltratorOS-0.1.9" "$sys"
for evidence in config map; do
    mv "$native/Images/InfiltratorOS-0.1.9.$evidence" "$work/$evidence"
    if bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$native/Modules/InfiltratorOS-0.1.9" "$sys" > "$work/no-$evidence.log" 2>&1; then
        echo "PCIe driver was accepted without $evidence" >&2; exit 1
    fi
    grep -Fq 'active driver missing from native build: pcieportdrv' "$work/no-$evidence.log"
    mv "$work/$evidence" "$native/Images/InfiltratorOS-0.1.9.$evidence"
done
printf '%s\n' 'CONFIG_PCIEPORTBUS=n' > "$native/Images/InfiltratorOS-0.1.9.config"
if bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$native/Modules/InfiltratorOS-0.1.9" "$sys" > "$work/disabled.log" 2>&1; then
    echo 'Disabled PCIe driver was accepted' >&2; exit 1
fi
grep -Fq 'active driver missing from native build: pcieportdrv' "$work/disabled.log"
rm "$sys/bus/pci/devices/port/driver/module"
mkdir -p "$work/empty-sys/bus"
if bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$modules" "$work/empty-sys" > "$work/empty.log" 2>&1; then
    echo 'Empty device scan was accepted' >&2; exit 1
fi
grep -Fq 'No active device drivers could be verified' "$work/empty.log"
# An otherwise complete index must not hide a missing actual-device driver.
cp "$modules/modules.dep" "$work/complete.dep"
for driver in snd_hda_intel intel_lpss_pci e1000e; do
    sed "/\/$driver\.ko:/d" "$work/complete.dep" > "$modules/modules.dep"
    if bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$modules" "$sys" > "$work/missing-$driver.log" 2>&1; then
        echo "Missing $driver module was accepted" >&2; exit 1
    fi
    grep -Fq "active driver missing from native build: $driver" "$work/missing-$driver.log"
done
cp "$work/complete.dep" "$modules/modules.dep"
rm "$modules/kernel/drivers/net/wireless/iwlwifi.ko.zst"
if bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$modules" "$sys" > "$work/missing-file.log" 2>&1; then
    echo 'Missing indexed module file was accepted' >&2; exit 1
fi
grep -Fq 'index references a missing file' "$work/missing-file.log"
printf '%s\n' 'kernel/drivers/unrelated.ko:' > "$modules/modules.dep"
mkdir -p "$modules/kernel/drivers"
: > "$modules/kernel/drivers/unrelated.ko"
if bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$modules" "$sys" > "$work/missing.log" 2>&1; then
    echo 'Missing Wi-Fi module was accepted' >&2; exit 1
fi
grep -Fq 'active driver missing from native build: iwlwifi' "$work/missing.log"
rm "$modules/modules.builtin"
if bash "$root/scripts/infiltrator/verify-host-drivers.sh" "$modules" "$sys" > /dev/null 2>&1; then
    echo 'Missing built-in index was accepted' >&2; exit 1
fi
echo 'NATIVE_HOST_DRIVER_INDEX_CHECK_PASS'
