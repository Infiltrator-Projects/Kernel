#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression tests: do not strip native filesystem mounts before SO VFS works."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/infiltrator/prune-external-filesystems.py"
SPEC = importlib.util.spec_from_file_location("native_filesystem_profile", SCRIPT)
PROFILE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROFILE)


class NativeFilesystemCompatibility(unittest.TestCase):
    def test_no_unqualified_kernel_replacement_is_retired(self):
        self.assertEqual(PROFILE.DISABLED, frozenset())
        for symbol in ("BTRFS_FS", "NTFS3_FS", "HFS_FS", "HFSPLUS_FS",
                       "EXFAT_FS", "XFS_FS", "AFFS_FS", "UFS_FS",
                       "EXT4_FS", "FAT_FS"):
            self.assertIn(symbol, PROFILE.PRESERVED)

    def test_native_drivers_survive_apply_and_check(self):
        original = ("CONFIG_XFS_FS=y\nCONFIG_BTRFS_FS=m\n"
                    "CONFIG_EXFAT_FS=m\nCONFIG_NTFS3_FS=y\n"
                    "CONFIG_HFS_FS=m\nCONFIG_HFSPLUS_FS=m\n"
                    "CONFIG_EXT4_FS=y\nCONFIG_FAT_FS=m\n")
        self.assertEqual(PROFILE.apply(original), original)
        self.assertIsNone(PROFILE.verify(original))
        self.assertEqual(PROFILE.apply(PROFILE.apply(original)), original)

    def test_no_mutation_of_duplicate_or_unterminated_lines(self):
        text = "# CONFIG_UFS_FS is not set\nCONFIG_UFS_FS=m\nCONFIG_TMPFS=y"
        self.assertEqual(PROFILE.apply(text), text)

    def test_invalid_tracked_setting_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "invalid"):
            PROFILE.apply("CONFIG_XFS_FS=invalid\n")

    def test_native_builder_selects_and_checks_mount_drivers(self):
        builder = (ROOT / "scripts/build-native.sh").read_text(encoding="utf-8")
        for symbol in ("BTRFS_FS", "HFS_FS", "HFSPLUS_FS",
                       "NTFS3_FS", "EXFAT_FS", "XFS_FS"):
            self.assertIn("--module " + symbol, builder)
        self.assertIn("Required native filesystem mount driver unavailable", builder)

    def test_cli_preserves_config_on_both_modes(self):
        with tempfile.TemporaryDirectory() as td:
            config = Path(td) / ".config"
            original = "CONFIG_BTRFS_FS=m\nCONFIG_NTFS3_FS=m\nCONFIG_EXT4_FS=y\n"
            config.write_text(original, encoding="utf-8")
            for mode in ("apply", "check"):
                result = subprocess.run([sys.executable, str(SCRIPT), mode,
                                         str(config)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("KERNEL_EXTERNAL_FS_PRESERVED", result.stdout)
                self.assertEqual(config.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
