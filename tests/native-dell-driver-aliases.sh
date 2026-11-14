#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Check real compiled module metadata against the observed Dell hardware IDs.
# This checks alias lookup only; it does not claim physical device operation.
set -euo pipefail
modules=${1:?staged native module directory required}
[[ -d $modules/kernel ]] || { echo 'Missing staged kernel module tree' >&2; exit 1; }
command -v modinfo >/dev/null

check_alias() {
    local name=$1 device=$2 path pattern matched=0
    local -a paths=()
    mapfile -d '' -t paths < <(find "$modules/kernel" -type f \
        \( -name "$name.ko" -o -name "$name.ko.gz" -o -name "$name.ko.xz" -o -name "$name.ko.zst" \) -print0)
    (( ${#paths[@]} == 1 )) || { echo "Expected one compiled $name module" >&2; return 1; }
    path=${paths[0]}
    local aliases
    aliases=$(modinfo -F alias "$path") || return 1
    while IFS= read -r pattern; do
        if [[ -n $pattern && $device == $pattern ]]; then matched=1; break; fi
    done <<< "$aliases"
    (( matched )) || { echo "$name does not match hardware alias $device" >&2; return 1; }
    printf 'Verified %s device alias\n' "$name"
}

check_alias iwlwifi 'pci:v00008086d00007E40sv00008086sd00004090bc02sc80i00'
check_alias intel_lpss_pci 'pci:v00008086d00007E78sv00001028sd00000CB9bc0Csc80i00'
check_alias intel_lpss_pci 'pci:v00008086d00007E7Bsv00001028sd00000CB9bc0Csc80i00'
check_alias snd_hda_intel 'pci:v00008086d00007E28sv00001028sd00000CB9bc04sc03i00'
check_alias e1000e 'pci:v00008086d0000550Asv00001028sd00000CB9bc02sc00i00'
# The ACPI HID transport is representative; the laptop-specific touchpad
# binding and actual input operation still require a physical test.
check_alias i2c-hid-acpi 'acpi:PNP0C50:'
echo 'NATIVE_DELL_DRIVER_ALIAS_PASS (not physical hardware qualification)'
