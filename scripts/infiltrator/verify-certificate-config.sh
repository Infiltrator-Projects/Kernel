#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fail before an expensive build if Kbuild's generated certificate settings
# disagree with the actual .config (e.g. stale auto.conf after a prior failure).
set -euo pipefail
if (( $# != 3 )); then
  printf '%s\n' 'Usage: verify-certificate-config.sh SOURCE_TREE BUILD_OBJECT_DIR CONFIG_FILE' >&2
  exit 2
fi
source_tree=$1
object_tree=$2
config_file=$3
auto_config="$object_tree/include/config/auto.conf"
[[ -f "$config_file" ]] || { echo "Kernel: ERROR: missing final .config" >&2; exit 1; }
[[ -f "$auto_config" ]] || { echo "Kernel: ERROR: missing generated auto.conf; regenerate config before compiling" >&2; exit 1; }
# .config quotes strings, while include/config/auto.conf does not.
# The distinction is in scripts/kconfig/confdata.c (escape_string true/false).
# Normalize both forms before comparing; never evaluate the string contents.
value() {
  local key=$1 file=$2 raw
  raw=$(awk -v prefix="CONFIG_${key}=" 'index($0,prefix)==1 {print substr($0,length(prefix)+1); exit}' "$file")
  if (( ${#raw} >= 2 )) && [[ ${raw:0:1} == '"' && ${raw: -1} == '"' ]]; then
    raw=${raw:1:${#raw}-2}
  fi
  printf '%s' "$raw"
}
# Kconfig only exports *active* options to auto.conf. The saved .config
# may still contain a string default for a symbol whose dependencies are off.
# Comparing that dormant default with a missing auto.conf entry is a false
# positive. Conversely, an active setting must be generated and must match.
enabled() {
  grep -Fqx "CONFIG_$1=y" "$auto_config"
}
active_setting() {
  case "$1" in
    SYSTEM_TRUSTED_KEYS) enabled SYSTEM_TRUSTED_KEYRING ;;
    SYSTEM_REVOCATION_KEYS) enabled SYSTEM_REVOCATION_LIST ;;
    MODULE_SIG_KEY)
      enabled MODULE_SIG ||
        { enabled IMA_APPRAISE_MODSIG && enabled MODULES; } ;;
    *) return 1 ;;
  esac
}
for key in SYSTEM_TRUSTED_KEYS SYSTEM_REVOCATION_KEYS MODULE_SIG_KEY; do
  # Dormant Kconfig strings retained in .config are not effective inputs.
  if ! active_setting "$key"; then
    continue
  fi
  configured=$(value "$key" "$config_file")
  if ! grep -q "^CONFIG_${key}=" "$auto_config"; then
    if active_setting "$key"; then
      printf 'Kernel: ERROR: active %s is absent from generated auto.conf\n' "$key" >&2
      exit 1
    fi
    # Inactive values from the host config are not used to build the kernel.
    continue
  fi
  generated=$(value "$key" "$auto_config")
  if [[ "$configured" != "$generated" ]]; then
    printf 'Kernel: ERROR: stale generated Kbuild configuration for %s\n' "$key" >&2
    printf 'Kernel: .config=%q, auto.conf=%q\n' "$configured" "$generated" >&2
    exit 1
  fi
  case "$key" in
    MODULE_SIG_KEY)
      # Kbuild generates the ordinary local signing key if requested;
      # it need not exist before the build starts.
      [[ "$generated" != "certs/signing_key.pem" && "$generated" != pkcs11:* ]] || continue ;;
  esac
  [[ -n "$generated" ]] || continue
  read -r -a files <<< "$generated"
  for file in "${files[@]}"; do
    if [[ "$file" = /* ]]; then
      [[ -f "$file" ]] || { echo "Kernel: ERROR: $key references missing $file" >&2; exit 1; }
    elif [[ ! -f "$source_tree/$file" && ! -f "$object_tree/$file" ]]; then
      printf 'Kernel: ERROR: %s references missing %s\n' "$key" "$file" >&2
      exit 1
    fi
  done
done
printf '%s\n' "Kernel: Effective compilation certificate settings verified (no missing distro PEMs)."
