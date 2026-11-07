#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Catch old vendor cert references in generated include/config/auto.conf.
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/infiltrator/verify-certificate-config.sh
testdir=$(mktemp -d)
trap 'rm -rf -- "$testdir"' EXIT
mkdir -p "$testdir/obj/include/config"
cat > "$testdir/obj/.config" <<'CONFIG'
CONFIG_SYSTEM_TRUSTED_KEYS=""
CONFIG_SYSTEM_REVOCATION_KEYS=""
CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"
CONFIG
cp "$testdir/obj/.config" "$testdir/obj/include/config/auto.conf"
bash scripts/infiltrator/verify-certificate-config.sh "$PWD" "$testdir/obj" "$testdir/obj/.config" >/dev/null
sed -i 's@CONFIG_SYSTEM_TRUSTED_KEYS=""@CONFIG_SYSTEM_TRUSTED_KEYS="debian/canonical-certs.pem"@' "$testdir/obj/include/config/auto.conf"
if bash scripts/infiltrator/verify-certificate-config.sh "$PWD" "$testdir/obj" "$testdir/obj/.config" > "$testdir/stale.log" 2>&1; then
  echo 'FAIL: stale effective certificate settings went undetected' >&2
  exit 1
fi
grep -Fq 'stale generated Kbuild configuration' "$testdir/stale.log"
sed -i 's@CONFIG_SYSTEM_TRUSTED_KEYS="debian/canonical-certs.pem"@CONFIG_SYSTEM_TRUSTED_KEYS=""@' "$testdir/obj/include/config/auto.conf"
sed -i 's@CONFIG_SYSTEM_REVOCATION_KEYS=""@CONFIG_SYSTEM_REVOCATION_KEYS="debian/canonical-revoked-certs.pem"@' "$testdir/obj/include/config/auto.conf"
if bash scripts/infiltrator/verify-certificate-config.sh "$PWD" "$testdir/obj" "$testdir/obj/.config" > "$testdir/stale.log" 2>&1; then
  echo 'FAIL: stale effective revocation settings went undetected' >&2
  exit 1
fi
grep -Fq 'stale generated Kbuild configuration' "$testdir/stale.log"
echo 'PASS: Kbuild generated certificates match .config; stale Canonical PEM paths detected'
