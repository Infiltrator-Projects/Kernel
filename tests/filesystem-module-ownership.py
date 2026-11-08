#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression tests for native filesystem ownership and eventual .ko pruning."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts/infiltrator/audit-filesystem-modules.py"
SPEC = importlib.util.spec_from_file_location("filesystem_audit", TOOL)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class FilesystemOwnershipTest(unittest.TestCase):
    def test_shared_fat_requires_all_three_providers(self):
        values = {"FAT_FS": "m", "VFAT_FS": "m", "MSDOS_FS": "m"}
        partial = AUDIT.review(values, {"FAT12", "FAT16"})
        self.assertEqual(partial[0][0], "FAT")
        self.assertFalse(partial[0][3])
        fully_qualified = AUDIT.review(values, {"FAT12", "FAT16", "FAT32"})
        self.assertTrue(fully_qualified[0][3])
        self.assertEqual(len(fully_qualified[0][2]), 3)

    def test_ext4_cannot_be_pruned_while_ext2_or_ext3_pending(self):
        values = {"EXT4_FS": "y"}
        records = AUDIT.review(values, {"EXT4"})
        ext4 = next(row for row in records if row[0] == "EXT3/EXT4")
        self.assertFalse(ext4[3])
        records = AUDIT.review(values, {"EXT2", "EXT3", "EXT4"})
        ext4 = next(row for row in records if row[0] == "EXT3/EXT4")
        self.assertTrue(ext4[3])

    def test_affs_and_ufs_are_shared(self):
        values = {"AFFS_FS": "m", "UFS_FS": "m"}
        records = AUDIT.review(values, {"FFS", "UFS2"})
        self.assertFalse(next(row for row in records if row[0] == "Amiga OFS/FFS")[3])
        self.assertFalse(next(row for row in records if row[0] == "UFS")[3])

    def test_parser_and_failure_on_qualified_duplicate(self):
        with tempfile.TemporaryDirectory() as temp:
            config = Path(temp) / ".config"
            config.write_text(
                "CONFIG_EXFAT_FS=m\n"
                "CONFIG_HFS_FS=y\n"
                "# CONFIG_FAT_FS is not set\n",
                encoding="utf-8")
            values = AUDIT.parse_config(config)
            self.assertEqual(values["EXFAT_FS"], "m")
            self.assertEqual(values["FAT_FS"], "n")
            cmd = [sys.executable, str(TOOL), "--config", str(config), "--check"]
            before = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(before.returncode, 0, before.stderr)
            self.assertIn("RETAIN: exFAT", before.stdout)
            after = subprocess.run(
                cmd + ["--provider-qualified", "exFAT"],
                capture_output=True, text=True)
            self.assertEqual(after.returncode, 1, after.stderr)
            self.assertIn("DUPLICATE: exFAT", after.stdout)
            self.assertIn("RETAIN: HFS", after.stdout)


if __name__ == "__main__":
    unittest.main()
