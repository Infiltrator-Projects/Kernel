#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Regression tests for real Kconfig .config (quoted string) vs generated
# auto.conf (unquoted string) plus active/inactive cert dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/infiltrator/verify-certificate-config.sh
testdir=$(mktemp -d)
trap 'rm -rf -- "$testdir"' EXIT
obj="$testdir/obj"
mkdir -p "$obj/include/config"
config="$obj/.config"
auto="$obj/include/config/auto.conf"
verify() {
  bash scripts/infiltrator/verify-certificate-config.sh "$PWD" "$obj" "$config"
}
expect_failure() {
  local expected=$1
  if verify > "$testdir/result.log" 2>&1; then
    printf 'FAIL: expected preflight rejection: %s\n' "$expected" >&2
    exit 1
  fi
  if ! grep -Fq -- "$expected" "$testdir/result.log"; then
    cat "$testdir/result.log" >&2
    printf 'FAIL: unexpected preflight rejection; expected: %s\n' "$expected" >&2
    exit 1
  fi
}
cat > "$config" <<'CONFIG'
CONFIG_SYSTEM_TRUSTED_KEYRING=y
CONFIG_SYSTEM_REVOCATION_LIST=y
CONFIG_MODULES=y
CONFIG_MODULE_SIG=y
CONFIG_SYSTEM_TRUSTED_KEYS=""
CONFIG_SYSTEM_REVOCATION_KEYS=""
CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"
CONFIG
cat > "$auto" <<'AUTOCONF'
CONFIG_SYSTEM_TRUSTED_KEYRING=y
CONFIG_SYSTEM_REVOCATION_LIST=y
CONFIG_MODULES=y
CONFIG_MODULE_SIG=y
CONFIG_SYSTEM_TRUSTED_KEYS=
CONFIG_SYSTEM_REVOCATION_KEYS=
CONFIG_MODULE_SIG_KEY=certs/signing_key.pem
AUTOCONF
# The real generated format must succeed, including the locally generated
# Kbuild module-signing key that will not exist before compilation.
verify >/dev/null

# A stale or unavailable vendor path must be detected even if it appears in
# an unquoted auto.conf (previous tests only modelled quoted strings).
sed -i 's@^CONFIG_SYSTEM_TRUSTED_KEYS=$@CONFIG_SYSTEM_TRUSTED_KEYS=debian/canonical-certs.pem@' "$auto"
expect_failure 'stale generated Kbuild configuration for SYSTEM_TRUSTED_KEYS'
sed -i 's@^CONFIG_SYSTEM_TRUSTED_KEYS=debian/canonical-certs.pem$@CONFIG_SYSTEM_TRUSTED_KEYS=@' "$auto"
sed -i 's@^CONFIG_SYSTEM_REVOCATION_KEYS=$@CONFIG_SYSTEM_REVOCATION_KEYS=debian/canonical-revoked-certs.pem@' "$auto"
expect_failure 'stale generated Kbuild configuration for SYSTEM_REVOCATION_KEYS'
sed -i 's@^CONFIG_SYSTEM_REVOCATION_KEYS=debian/canonical-revoked-certs.pem$@CONFIG_SYSTEM_REVOCATION_KEYS=@' "$auto"

# A missing active setting is not equivalent to an inactive one.
sed -i '/^CONFIG_MODULE_SIG_KEY=/d' "$auto"
expect_failure 'active MODULE_SIG_KEY is absent'
printf '%s\n' 'CONFIG_MODULE_SIG_KEY=certs/signing_key.pem' >> "$auto"
verify >/dev/null
sed -i '/^CONFIG_SYSTEM_TRUSTED_KEYS=/d' "$auto"
expect_failure 'active SYSTEM_TRUSTED_KEYS is absent'
printf '%s\n' 'CONFIG_SYSTEM_TRUSTED_KEYS=' >> "$auto"
verify >/dev/null

# Matching but unavailable certificates are also an error.
sed -i 's@^CONFIG_SYSTEM_TRUSTED_KEYS=""$@CONFIG_SYSTEM_TRUSTED_KEYS="debian/canonical-certs.pem"@' "$config"
sed -i 's@^CONFIG_SYSTEM_TRUSTED_KEYS=$@CONFIG_SYSTEM_TRUSTED_KEYS=debian/canonical-certs.pem@' "$auto"
expect_failure 'SYSTEM_TRUSTED_KEYS references missing debian/canonical-certs.pem'

# With signing and trust options disabled, .config may retain dormant defaults.
sed -i 's@^CONFIG_SYSTEM_TRUSTED_KEYRING=y$@# CONFIG_SYSTEM_TRUSTED_KEYRING is not set@' "$auto"
sed -i 's@^CONFIG_SYSTEM_REVOCATION_LIST=y$@# CONFIG_SYSTEM_REVOCATION_LIST is not set@' "$auto"
sed -i 's@^CONFIG_MODULE_SIG=y$@# CONFIG_MODULE_SIG is not set@' "$auto"
# The last matching source string is deliberately different and inactive.
sed -i 's@^CONFIG_MODULE_SIG_KEY=certs/signing_key.pem$@CONFIG_MODULE_SIG_KEY=@' "$auto"
verify >/dev/null

echo 'PASS: real Kbuild string serialization, active/missing certificate paths, and inactive defaults'
