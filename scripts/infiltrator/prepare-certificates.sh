#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepare an out-of-tree, independently built Linux kernel to use only
# certificate inputs actually available to this source checkout.
# Distribution kernel configurations may refer to files generated or supplied
# separately by the distribution's official signing/packaging infrastructure.
set -euo pipefail
if (( $# != 2 )); then
  echo "Usage: prepare-certificates.sh SOURCE_TREE BUILD_OBJECT_DIR" >&2
  exit 2
fi
srctree=$1
objtree=$2
config="$objtree/.config"
[[ -f "$config" && -x "$srctree/scripts/config" ]] || {
  echo "Kernel: ERROR: missing .config or scripts/config" >&2
  exit 1
}
log() { echo "Kernel: $*" >&2; }

config_value() {
  local option=$1
  sed -n "s/^CONFIG_${option}=\"\\(.*\\)\"$/\\1/p" "$config" | head -n 1
}

file_available() {
  local filename=$1
  [[ -z "$filename" ]] && return 0
  if [[ "$filename" = /* ]]; then
    [[ -f "$filename" ]]
  else
    [[ -f "$srctree/$filename" || -f "$objtree/$filename" ]]
  fi
}

# A distro may reference trusted and revoked PEM bundles which are supplied
# only during its internal kernel packaging. These cannot be invented or
# replaced with empty fake PEM files. An independent image cannot claim to
# inherit the vendor's trust/revocation policy without those certificates.
for option in SYSTEM_TRUSTED_KEYS SYSTEM_REVOCATION_KEYS; do
  value=$(config_value "$option")
  [[ -n "$value" ]] || continue
  missing=0
  read -r -a files <<< "$value"
  for f in "${files[@]}"; do
    if ! file_available "$f"; then
      missing=1
      break
    fi
  done
  if (( missing )); then
    log "NOTICE: $option references missing distribution certificate input: $value"
    log "NOTICE: omitting that vendor bundle from this independent build; the original config is unchanged"
    "$srctree/scripts/config" --file "$config" --set-str "$option" ""
  fi
done

# When the distro's module signing key is unavailable, use the ordinary
# kernel-generated *local* signing key, not a copied vendor signing identity.
signing_key=$(config_value MODULE_SIG_KEY)
if [[ -n "$signing_key" && "$signing_key" != certs/signing_key.pem ]] &&
   [[ "$signing_key" != pkcs11:* ]] &&
   ! file_available "$signing_key"; then
  log "NOTICE: module signing key $signing_key is unavailable; generating a local key via Kbuild"
  "$srctree/scripts/config" --file "$config" --set-str MODULE_SIG_KEY certs/signing_key.pem
fi
