#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Keep independent non-boot filesystem VFS modules out of native Kernel builds.

The Linux sources stay in fs/ for provenance and code comparison, but the
native builder's *effective* .config must not compile the independent formats
again.  Do not alter the host's /boot/config-* or unrelated Kconfig settings.
The EFI FAT bootstrap, legacy FAT/EXT fallback and shared VFS remain enabled
according to the host's original configuration.

WARNING: Linux-6.12.107 provider .ko releases are NOT module-ABI-compatible
with the independent InfiltratorOS Kernel 0.1.1.  Missing format drivers must
be rebuilt against its Module.symvers before native-runtime use.  Pruning
these optional drivers is an explicit native build/boot-profile choice.
"""
import argparse
from pathlib import Path
import re
import sys

# One in-tree driver may cover several independently owned formats.  Prune
# its entire generic kernel format group, not only one package's variant.
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
DISABLED = frozenset(symbol for group in NONBOOT_FORMATS.values()
                     for symbol in group)
# Do not disable any storage transport, VFS helpers, initramfs tools or
# filesystems required by the existing bootstrap/fallback configurations.
PRESERVED = frozenset({
    "FAT_FS", "VFAT_FS", "MSDOS_FS", "EXT2_FS", "EXT3_FS", "EXT4_FS",
    "JBD2", "FS_MBCACHE", "SQUASHFS", "CRAMFS", "TMPFS", "EFIVAR_FS",
    "PROC_FS", "SYSFS", "DEVTMPFS", "RAMFS", "OVERLAY_FS",
})
assert DISABLED.isdisjoint(PRESERVED)

ACTIVE = re.compile(r"^CONFIG_([A-Z0-9_]+)=(.*)$")
NOT_SET = re.compile(r"^# CONFIG_([A-Z0-9_]+) is not set$")


def config_symbol(line):
    """Return (symbol, state) for a Kconfig setting or (None, None)."""
    active = ACTIVE.fullmatch(line)
    if active:
        return active.group(1), active.group(2)
    disabled = NOT_SET.fullmatch(line)
    if disabled:
        return disabled.group(1), "n"
    return None, None


def apply(text):
    """Idempotently force all retired driver symbols off in build-local config."""
    result = []
    seen = set()
    for line in text.splitlines(keepends=True):
        symbol, state = config_symbol(line.rstrip("\r\n"))
        if symbol not in DISABLED:
            result.append(line)
            continue
        if state not in ("y", "m", "n"):
            raise ValueError(f"invalid kernel filesystem setting: {line.strip()}")
        if symbol not in seen:
            result.append(f"# CONFIG_{symbol} is not set\n")
            seen.add(symbol)
    missing = DISABLED - seen
    if missing:
        if result and not result[-1].endswith("\n"):
            result.append("\n")
        result.append("# Independent InfiltratorOS non-boot filesystem providers\n")
        for symbol in sorted(missing):
            result.append(f"# CONFIG_{symbol} is not set\n")
    return "".join(result)


def verify(text):
    """Verify effective Kconfig: neither =y nor =m may survive olddefconfig."""
    active = []
    for line in text.splitlines():
        symbol, state = config_symbol(line)
        if symbol in DISABLED and state != "n":
            active.append(f"CONFIG_{symbol}={state}")
    if active:
        raise ValueError("superseded kernel filesystems still selected: " +
                         ", ".join(sorted(active)))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("apply", "check"))
    parser.add_argument("config", type=Path)
    args = parser.parse_args(argv)
    if not args.config.is_file():
        parser.error(f"missing kernel .config: {args.config}")
    try:
        original = args.config.read_text(encoding="utf-8")
        if args.mode == "apply":
            rewritten = apply(original)
            if original != rewritten:
                args.config.write_text(rewritten, encoding="utf-8")
            verify(rewritten)
            print("KERNEL_EXTERNAL_FS_PRUNE_APPLIED: " +
                  ", ".join(sorted(DISABLED)))
        else:
            verify(original)
            print("KERNEL_EXTERNAL_FS_PRUNE_PASS: no retired =y or =m drivers")
    except (OSError, UnicodeError, ValueError) as exc:
        print("KERNEL_EXTERNAL_FS_PRUNE_FAIL: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
