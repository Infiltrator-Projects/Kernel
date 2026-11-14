#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Check the staged native package for the modules currently bound to host
# devices. This reads sysfs and package indexes only; it never loads drivers.
set -euo pipefail
modules=${1:?native module directory required}
sysroot=${2:-/sys}
fail() { printf 'Kernel hardware check: ERROR: %s\n' "$*" >&2; exit 1; }
[[ $modules == /* && -d $modules && ! -L $modules ]] || fail 'Invalid native module directory'
[[ $sysroot == /* && -d $sysroot ]] || fail 'Invalid sysfs directory'
[[ -f $modules/modules.dep && -f $modules/modules.builtin ]] ||
    fail 'Native driver indexes are incomplete'

# Kbuild's two text indexes cover loadable and built-in drivers. Normalize
# kernel module names the same way kmod treats hyphens and underscores.
declare -A provided=() active=()
for index in modules.dep modules.builtin; do
    while IFS= read -r line || [[ -n $line ]]; do
        path=${line%%:*}
        name=${path##*/}
        case "$name" in
            *.ko|*.ko.gz|*.ko.xz|*.ko.zst)
                case "$path" in /*|../*|*/../*|*/..) fail 'Unsafe native driver index path' ;; esac
                if [[ $index == modules.dep && ! -f $modules/$path ]]; then
                    fail "Native driver index references a missing file: $path"
                fi
                name=${name%%.ko*}
                name=${name//-/_}
                [[ $name =~ ^[[:alnum:]_]+$ ]] || fail 'Malformed native driver index'
                provided["$name"]=1 ;;
        esac
    done < "$modules/$index"
done

# A module symlink is present only for devices bound to a modular or
# registered built-in driver. Other buses and userspace-only devices are not
# claimed as tested. Multiple devices can share the same module.
for bus in pci usb i2c acpi hid serio platform spi; do
    for link in "$sysroot/bus/$bus/devices/"*/driver/module; do
        [[ -L $link ]] || continue
        resolved=$(readlink -f -- "$link") || fail "Cannot resolve active $bus driver"
        name=${resolved##*/}
        name=${name//-/_}
        [[ $name =~ ^[[:alnum:]_]+$ ]] || fail "Invalid active $bus driver name"
        active["$name"]=1
    done
done

missing=0
for name in "${!active[@]}"; do
    if [[ -z ${provided[$name]+found} ]]; then
        printf 'Kernel hardware check: active driver missing from native build: %s\n' "$name" >&2
        missing=$((missing+1))
    fi
done
(( missing == 0 )) || fail 'Native kernel not installed; existing boot and kernel were preserved'
printf 'Kernel hardware check: %s active device-driver module(s) present in native indexes.\n' "${#active[@]}"
printf '%s\n' 'Kernel hardware check: this does not verify firmware, device operation, or physical boot.'
