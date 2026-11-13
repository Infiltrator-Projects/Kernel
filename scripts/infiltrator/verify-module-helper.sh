#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Verify the generated setting consumed by kernel/module/kmod.c.
set -euo pipefail
objects=${1:?prepared kernel object directory required}
version=${2:?native kernel version required}
header="$objects/include/generated/autoconf.h"
expected="#define CONFIG_MODPROBE_PATH \"/System/Kernel/Runtime/InfiltratorOS-$version/modprobe\""
if ! grep -Fqx -- "$expected" "$header"; then
    printf 'Kernel: ERROR: Generated kernel config lacks the native module helper for %s (%s)\n' \
        "$version" "$header" >&2
    exit 1
fi
