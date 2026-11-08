#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fast offline regressions for the cross-repository native boot harness."""
from __future__ import annotations

import gzip
import importlib.util
from pathlib import Path
import stat
import tempfile

path = Path(__file__).with_name("infiltratorfs-native-boot.py")
spec = importlib.util.spec_from_file_location("infiltratorfs_native_boot", path)
if spec is None or spec.loader is None:
    raise RuntimeError("Cannot import native boot harness")
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)


def main() -> None:
    assert boot.module_name(Path("infiltratorfs.ko.zst")) == "infiltratorfs"
    assert boot.module_name(Path("virtio-blk.ko")) == "virtio_blk"
    entry = boot.cpio("sample", stat.S_IFREG | 0o644, b"abc")
    assert entry[:6] == b"070701"
    fields = [int(entry[6+n*8:14+n*8], 16) for n in range(13)]
    assert fields[6] == 3 and fields[11] == 7
    assert len(entry) % 4 == 0 and b"sample\x00" in entry and b"abc" in entry

    with tempfile.TemporaryDirectory(prefix="infiltratoros-preflight-") as tmp:
        root = Path(tmp)
        modules = root / "modules"
        (modules / "a").mkdir(parents=True)
        (modules / "b").mkdir(parents=True)
        (modules / "a" / "example.ko").write_bytes(b"a")
        (modules / "b" / "example.ko").write_bytes(b"b")
        config = root / "config"
        config.write_text("CONFIG_VIRTIO_PCI=y\nCONFIG_VIRTIO_BLK=y\n")
        try:
            boot.modules_for_vm(modules, root / "infiltratorfs.ko",
                                "0.1.0-infiltrator", config)
        except ValueError as exc:
            assert "Ambiguous native module" in str(exc), str(exc)
        else:
            raise AssertionError("Duplicate module names must be rejected")

        busybox = root / "busybox"
        busybox.write_bytes(b"synthetic-static-busybox")
        initrd = root / "initrd"
        boot.make_initramfs(busybox, [], "9.8.7-infiltrator", initrd,
                            "0" * 64, "9.8.7")
        payload = gzip.decompress(initrd.read_bytes())
        assert b"InfiltratorOS-9.8.7.img" in payload
        assert b"9.8.7-infiltrator" in payload
        assert b"INFS_REBOOT_PERSISTENCE_PASS" in payload
        # Enumerate the actual guest devices, allow bounded registration delay,
        # and reject a foreign mount before deciding the expected disk is absent.
        assert b"/sys/class/block/*" in payload
        assert b"for attempt in 1 2 3 4 5 6 7 8 9 10" in payload
        assert b"WRONG_VOLUME_UNMOUNT" in payload
        assert b"/dev/vdb /dev/vda /dev/sdb /dev/sda" not in payload
    print("THREE_WAY_PREFLIGHT_PASS: module uniqueness, CPIO and product ABI")


if __name__ == "__main__":
    main()
