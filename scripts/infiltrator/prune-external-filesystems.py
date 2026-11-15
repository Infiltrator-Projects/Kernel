#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Preserve host filesystem VFS support until the Common V2 kernel bridge works.

The current native kernel must not discard Linux's tested filesystem drivers
merely because an independently installed Common V2 .so exists. That .so
currently serves qualified desktop/BOOT consumers, not ordinary Linux VFS
mounts. The apply/check CLI is retained for existing build integrations and
validates the input WITHOUT changing its bytes.
"""
import argparse
from pathlib import Path
import re
import sys

NONBOOT_FORMATS = {
    "exFAT": ("EXFAT_FS",),
    "NTFS": ("NTFS3_FS", "NTFS_FS"),
    "XFS": ("XFS_FS",),
    "Btrfs": ("BTRFS_FS",),
    "HFS": ("HFS_FS",),
    "HFSPlus/HFSX": ("HFSPLUS_FS",),
    "Amiga OFS/FFS": ("AFFS_FS",),
    "Minix": ("MINIX_FS",),
    "UFS1/UFS2": ("UFS_FS",),
}
# No in-tree format can be retired before an actual kernel VFS replacement
# mounts and reads/writes independent test media.
DISABLED = frozenset()
PRESERVED = frozenset({
    "FAT_FS", "VFAT_FS", "MSDOS_FS", "EXT2_FS", "EXT3_FS", "EXT4_FS",
    "JBD2", "FS_MBCACHE", "SQUASHFS", "CRAMFS", "TMPFS", "EFIVAR_FS",
    "PROC_FS", "SYSFS", "DEVTMPFS", "RAMFS", "OVERLAY_FS",
}).union(*(frozenset(group) for group in NONBOOT_FORMATS.values()))
ACTIVE = re.compile(r"^CONFIG_([A-Z0-9_]+)=(.*)$")
WATCHED = frozenset(item for group in NONBOOT_FORMATS.values() for item in group)


def verify(config):
    """Validate tracked settings without imposing a value or modifying text."""
    for line in config.splitlines():
        match = ACTIVE.fullmatch(line)
        if match and match.group(1) in WATCHED and match.group(2) not in (
            "y", "m", "n"
        ):
            raise ValueError(f"invalid kernel filesystem setting: {line}")


def apply(config):
    """Return the exact original host configuration, validated and unchanged."""
    verify(config)
    return config


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("apply", "check"))
    parser.add_argument("config", type=Path)
    args = parser.parse_args(argv)
    if not args.config.is_file():
        parser.error(f"missing kernel .config: {args.config}")
    try:
        original = args.config.read_text(encoding="utf-8")
        verify(original)
        print("KERNEL_EXTERNAL_FS_PRESERVED")
    except (OSError, UnicodeError, ValueError) as exc:
        print("KERNEL_EXTERNAL_FS_PRESERVE_FAIL: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
