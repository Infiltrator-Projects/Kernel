#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/build-native.sh
bash scripts/build-native.sh --help | grep -q -- '--build-only'
grep -q -- 'linux-headers-' scripts/build-native.sh
grep -q -- 'LOCALVERSION=-infiltrator' scripts/build-native.sh
grep -q -- 'bindeb-pkg' scripts/build-native.sh
echo "PASS: syntax and CLI-contract checks (NOT a complete kernel build)"

# Ensure these Kbuild additions are defined once in the final Make invocation.
make -n configure-only SKIP_DEPS=1 | grep -Fq 'scripts/build-native.sh --configure-only'
make -n build-only SKIP_DEPS=1 | grep -Fq 'scripts/build-native.sh --build-only'
# The AppArmor description must be quoted: otherwise Kconfig warns.
grep -Fq 'bool "Enable AppArmor packet mediation by default"' security/apparmor/Kconfig
