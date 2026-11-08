#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Audit duplicate filesystem code in a built kernel configuration.

The external filesystem engines remain owned by their Filesystem-* projects.
This tool only detects possible duplicate kernel implementations.  It does
not change a .config, suppress builds or claim module runtime qualification.
In particular, one kernel FAT/AFFS/UFS implementation covers several
independently owned formats; it must remain until EVERY owner is qualified.
"""
import argparse
from pathlib import Path
import re
import sys

# All names are independently owned repositories Filesystem-<name>.
# Only upstream filesystem drivers with a matching independent provider
# appear here.  ProcFS, SysFS, initramfs and unrelated network FS remain.
GROUPS = (
    ("FAT", ("FAT12", "FAT16", "FAT32"),
     ("FAT_FS", "MSDOS_FS", "VFAT_FS")),
    ("exFAT", ("exFAT",), ("EXFAT_FS",)),
    ("NTFS", ("NTFS",), ("NTFS3_FS", "NTFS_FS")),
    ("EXT2", ("EXT2",), ("EXT2_FS",)),
    ("EXT3/EXT4", ("EXT2", "EXT3", "EXT4"), ("EXT4_FS",)),
    ("XFS", ("XFS",), ("XFS_FS",)),
    ("Btrfs", ("Btrfs",), ("BTRFS_FS",)),
    ("HFS", ("HFS",), ("HFS_FS",)),
    ("HFSPlus", ("HFSPlus",), ("HFSPLUS_FS",)),
    ("Amiga OFS/FFS", ("OFS", "FFS"), ("AFFS_FS",)),
    ("Minix", ("Minix",), ("MINIX_FS",)),
    ("UFS", ("UFS1", "UFS2"), ("UFS_FS",)),
)


def parse_config(path):
    values = {}
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"CONFIG_([A-Z0-9_]+)=(y|m)", raw)
        if match:
            values[match.group(1)] = match.group(2)
        else:
            match = re.fullmatch(r"# CONFIG_([A-Z0-9_]+) is not set", raw)
            if match:
                values[match.group(1)] = "n"
    return values


def review(values, provider_claims):
    """Return source groups with source, owner and compiled-module status."""
    reports = []
    for group, owners, symbols in GROUPS:
        active = {symbol: values.get(symbol, "?") for symbol in symbols
                  if values.get(symbol) in ("y", "m")}
        ready = all(owner in provider_claims for owner in owners)
        reports.append((group, owners, active, ready))
    return reports


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path,
                        help="Kernel .config or staged InfiltratorOS .config")
    parser.add_argument("--provider-qualified", action="append", default=[],
                        metavar="NAME",
                        help="Provider declared qualified by the caller; no validation is implied")
    parser.add_argument("--check", action="store_true",
                        help="Fail if declared-qualified providers duplicate compiled kernel filesystems")
    args = parser.parse_args(argv)
    valid = {owner for _, owners, _ in GROUPS for owner in owners}
    unknown = set(args.provider_qualified) - valid
    if unknown:
        parser.error("unknown providers: " + ", ".join(sorted(unknown)))
    try:
        records = review(parse_config(args.config), set(args.provider_qualified))
    except OSError as exc:
        parser.error(str(exc))

    duplicates = 0
    for group, owners, active, ready in records:
        if not active:
            continue
        modes = ", ".join("CONFIG_%s=%s" % item for item in active.items())
        if ready:
            duplicates += 1
            print("DUPLICATE: %s: %s; independent owner(s): %s" %
                  (group, modes, ", ".join(owners)))
        else:
            missing = [owner for owner in owners
                       if owner not in args.provider_qualified]
            print("RETAIN: %s: %s; unqualified provider(s): %s" %
                  (group, modes, ", ".join(missing)))
    if args.check and duplicates:
        print("FAIL: qualified independent filesystem also compiled into kernel",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
