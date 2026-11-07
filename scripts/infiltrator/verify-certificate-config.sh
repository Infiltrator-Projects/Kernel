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
value() {
  local key=$1 file=$2
  sed -n "s/^CONFIG_${key}=\"\\(.*\\)\"$/\\1/p" "$file" | head -n 1
}
for key in SYSTEM_TRUSTED_KEYS SYSTEM_REVOCATION_KEYS MODULE_SIG_KEY; do
  configured=$(value "$key" "$config_file")
  generated=$(value "$key" "$auto_config")
  if [[ "$configured" != "$generated" ]]; then
    printf 'Kernel: ERROR: stale generated Kbuild configuration for %s\n' "$key" >&2
    printf 'Kernel: .config=%q, auto.conf=%q\n' "$configured" "$generated" >&2
    exit 1
  fi
  case "$key" in
    MODULE_SIG_KEY)
      # Kbuild may create its default local signing certificate during build.
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
