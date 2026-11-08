#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test the actual native filesystem-prune configuration algorithm."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/infiltrator/prune-external-filesystems.py"
SPEC = importlib.util.spec_from_file_location("prune_external", SCRIPT)
PRUNE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRUNE)


class NonbootFilesystemBuildProfile(unittest.TestCase):
    def test_known_independent_groups_and_boot_preservation(self):
        self.assertIn("XFS_FS", PRUNE.DISABLED)
        self.assertIn("BTRFS_FS", PRUNE.DISABLED)
        self.assertIn("UFS_FS", PRUNE.DISABLED)
        self.assertIn("AFFS_FS", PRUNE.DISABLED)
        self.assertTrue(PRUNE.DISABLED.isdisjoint(PRUNE.PRESERVED))
        # EXT2 is being qualified in another repository; FAT/EXT remain.
        self.assertTrue({"EXT2_FS", "EXT4_FS", "FAT_FS",
                         "VFAT_FS", "MSDOS_FS", "JBD2"} <= PRUNE.PRESERVED)

    def test_builtins_and_modules_are_both_pruned(self):
        old = ("CONFIG_XFS_FS=y\nCONFIG_BTRFS_FS=m\n"
               "CONFIG_EXFAT_FS=m\nCONFIG_NTFS3_FS=y\n"
               "CONFIG_EXT2_FS=m\nCONFIG_EXT4_FS=y\n"
               "CONFIG_FAT_FS=m\nCONFIG_VFAT_FS=m\n"
               "CONFIG_JBD2=y\nCONFIG_TMPFS=y\n")
        new = PRUNE.apply(old)
        PRUNE.verify(new)
        self.assertEqual(new, PRUNE.apply(new), "not idempotent")
        for symbol in ("XFS_FS", "BTRFS_FS", "EXFAT_FS", "NTFS3_FS"):
            self.assertIn(f"# CONFIG_{symbol} is not set", new)
            self.assertNotIn(f"CONFIG_{symbol}=m", new)
            self.assertNotIn(f"CONFIG_{symbol}=y", new)
        for row in ("CONFIG_EXT2_FS=m", "CONFIG_EXT4_FS=y",
                    "CONFIG_FAT_FS=m", "CONFIG_VFAT_FS=m",
                    "CONFIG_JBD2=y", "CONFIG_TMPFS=y"):
            self.assertIn(row, new)

    def test_verify_fails_if_kconfig_reenables_a_driver(self):
        for state in ("y", "m"):
            with self.subTest(state=state):
                with self.assertRaisesRegex(ValueError, "XFS_FS"):
                    PRUNE.verify(f"CONFIG_XFS_FS={state}\n")
        # Kconfig legitimately removes symbols unavailable to this version.
        PRUNE.verify("CONFIG_EXT4_FS=y\n")

    def test_duplicate_entries_are_normalized_without_side_effects(self):
        source = ("# CONFIG_UFS_FS is not set\nCONFIG_UFS_FS=m\n"
                  "CONFIG_EXT4_FS=y\n")
        new = PRUNE.apply(source)
        self.assertEqual(new.count("# CONFIG_UFS_FS is not set"), 1)
        self.assertEqual(new.count("CONFIG_EXT4_FS=y"), 1)
        self.assertEqual(new, PRUNE.apply(new))

    def test_fail_closed_on_invalid_syntax(self):
        with self.assertRaisesRegex(ValueError, "invalid"):
            PRUNE.apply("CONFIG_XFS_FS=unexpected\n")

    def test_real_cli_never_changes_host_or_unrelated_setting(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = Path(td) / ".config"
            cfg.write_text("CONFIG_XFS_FS=m\nCONFIG_EXT4_FS=y\n"
                           "CONFIG_FAT_FS=y\n", encoding="utf-8")
            apply = subprocess.run([sys.executable, str(SCRIPT), "apply",
                                    str(cfg)], capture_output=True, text=True)
            self.assertEqual(apply.returncode, 0, apply.stderr)
            self.assertIn("KERNEL_EXTERNAL_FS_PRUNE_APPLIED", apply.stdout)
            check = subprocess.run([sys.executable, str(SCRIPT), "check",
                                    str(cfg)], capture_output=True, text=True)
            self.assertEqual(check.returncode, 0, check.stderr)
            self.assertIn("CONFIG_EXT4_FS=y", cfg.read_text())
            self.assertIn("CONFIG_FAT_FS=y", cfg.read_text())
            cfg.write_text(cfg.read_text() + "CONFIG_XFS_FS=m\n")
            bad = subprocess.run([sys.executable, str(SCRIPT), "check",
                                  str(cfg)], capture_output=True, text=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("XFS_FS", bad.stderr)


if __name__ == "__main__":
    unittest.main()
