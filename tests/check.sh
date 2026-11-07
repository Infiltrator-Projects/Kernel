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

# Regression: distro-built kernel configs may depend on private Canonical
# certificate files absent from the published source package. The builder
# must prepare the private build .config without altering the input baseline.
bash -n scripts/infiltrator/prepare-certificates.sh
testdir=$(mktemp -d)
trap 'rm -rf "$testdir"' EXIT
cat > "$testdir/.config" <<'CONFIG'
CONFIG_SYSTEM_TRUSTED_KEYS="debian/infiltrator-ci-missing-trusted.pem"
CONFIG_SYSTEM_REVOCATION_KEYS="debian/infiltrator-ci-missing-revoked.pem"
CONFIG_MODULE_SIG_KEY="debian/infiltrator-ci-missing-signing.pem"
CONFIG
bash scripts/infiltrator/prepare-certificates.sh "$PWD" "$testdir"
grep -Fxq 'CONFIG_SYSTEM_TRUSTED_KEYS=""' "$testdir/.config"
grep -Fxq 'CONFIG_SYSTEM_REVOCATION_KEYS=""' "$testdir/.config"
grep -Fxq 'CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"' "$testdir/.config"

# Certificate inputs that actually exist must be retained, not discarded.
printf '%s\n' 'test fixture, not a certificate' > "$testdir/existing.pem"
printf 'CONFIG_SYSTEM_TRUSTED_KEYS="%s/existing.pem"\n' "$testdir" > "$testdir/.config"
bash scripts/infiltrator/prepare-certificates.sh "$PWD" "$testdir"
grep -Fxq "CONFIG_SYSTEM_TRUSTED_KEYS=\"$testdir/existing.pem\"" "$testdir/.config"
echo "PASS: certificate input handling preserves available keys and reports missing distro keys"

# Native kernel staging must honour the InfiltratorOS /System/Kernel contract.
bash tests/native-contract.sh

# The native Debian generator uses independent InfiltratorOS package names and
# component versions while preserving the exact kernel/module ABI as metadata.
bash tests/package-identity.sh

# Certificate path changes must propagate to generated Kbuild auto.conf.
bash tests/effective-certificates.sh

# The first-party wrapper must restart Kbuild outside its parent's recursive sentinel.
bash -n scripts/infiltrator/run-kbuild.sh
grep -Fq 'unset sub_make_done' scripts/infiltrator/run-kbuild.sh
[[ $(grep -Fc 'bash "$root/scripts/infiltrator/run-kbuild.sh"' scripts/build-native.sh) -eq 4 ]]
