#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Filesystem FUSE is a forbidden dependency and a forbidden kernel transport.
# This gate intentionally does not match unrelated hardware eFuses/OTP fuses.
set -euo pipefail
cd "$(dirname "$0")/.."

for path in \
    fs/fuse \
    include/uapi/linux/fuse.h \
    include/uapi/linux/virtio_fs.h \
    Documentation/filesystems/fuse \
    Documentation/filesystems/virtiofs.rst \
    tools/testing/selftests/filesystems/fuse \
    tools/testing/selftests/memfd/fuse_mnt.c \
    tools/testing/selftests/memfd/fuse_test.c \
    tools/testing/selftests/memfd/run_fuse_test.sh; do
  if [[ -e "$path" ]]; then
    echo "PROHIBITED filesystem FUSE source: $path" >&2
    exit 1
  fi
done

if grep -Eq 'fs/fuse/|CONFIG_(FUSE_FS|CUSE|VIRTIO_FS)|fuse/' fs/Kconfig fs/Makefile; then
  echo 'PROHIBITED filesystem FUSE Kbuild/Kconfig reference' >&2
  exit 1
fi

if grep -Ern '^CONFIG_(FUSE_FS|CUSE|VIRTIO_FS|FUSE_DAX|FUSE_PASSTHROUGH|FUSE_IO_URING)=[ym]$' arch/*/configs 2>/dev/null; then
  echo 'PROHIBITED filesystem FUSE in checked-in architecture config' >&2
  exit 1
fi

# First-party build and install scripts must not add any FUSE packages.
if grep -Eirn '(libfuse[0-9-]*|fusermount|fuse-overlayfs|(^|[^a-z])fuse3([^a-z]|$)|sshfs)' \
    scripts/package scripts/infiltrator .github/workflows \
    --include='*.sh' --include='*.yml' --include='*.yaml' \
    --exclude='import-kernel-source.yml' 2>/dev/null; then
  echo 'PROHIBITED filesystem FUSE dependency in build, install, or CI' >&2
  exit 1
fi

# Reject native builds which silently disable or replace the negative config gate.
grep -Fq "CONFIG_(FUSE_FS|CUSE|VIRTIO_FS|FUSE_DAX|FUSE_PASSTHROUGH|FUSE_IO_URING)=[ym]" scripts/build-native.sh || {
  echo 'Missing fail-closed runtime kernel configuration check' >&2
  exit 1
}
echo 'PASS: kernel filesystem FUSE source, config and installation ban'
