#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Real Boot -> Format 0.19 -> InfiltratorOS Kernel -> InfiltratorFS VFS trial.

Every disk, ESP, UEFI variable store and log is a disposable regular file.
Only Boot and the InfiltratorFS EFI driver live on the FAT32 bootstrap ESP.
The *only* copies of the kernel and initramfs are on the InfiltratorFS disk.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import lzma
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys


def run(*args: object) -> None:
    subprocess.run([str(x) for x in args], check=True)


def cmd_out(*args: object) -> str:
    return subprocess.check_output([str(x) for x in args], text=True).strip()


def require(path: Path) -> Path:
    path = path.resolve()
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing required file: {path}")
    return path


def cpio(name: str, mode: int, payload: bytes = b"", major: int = 0, minor: int = 0) -> bytes:
    filename = name.encode() + b"\0"
    fields = (1, mode, 0, 0, 1, 0, len(payload), 0, 0, major, minor, len(filename), 0)
    result = b"070701" + b"".join(f"{field:08x}".encode() for field in fields) + filename
    result += bytes(-len(result) % 4)
    result += payload
    return result + bytes(-len(payload) % 4)


def module_name(path: Path) -> str:
    return re.sub(r"\.ko(?:\.(?:xz|zst|gz))?$", "", path.name).replace("-", "_")


def module_data(path: Path) -> bytes:
    if path.name.endswith(".ko.xz"):
        return lzma.decompress(path.read_bytes())
    if path.name.endswith(".ko.gz"):
        return gzip.decompress(path.read_bytes())
    if path.name.endswith(".ko.zst"):
        return subprocess.check_output(["zstd", "-d", "-q", "-c", str(path)])
    return path.read_bytes()


def modules_for_vm(module_root: Path, infil_module: Path, kernel_release: str,
                   kernel_config: Path) -> list[tuple[str, bytes]]:
    config = kernel_config.read_text()
    module_index: dict[str, Path] = {}
    for path in module_root.rglob("*.ko*"):
        if path.is_file() and re.search(r"\.ko(?:\.(?:xz|zst|gz))?$", path.name):
            module_index.setdefault(module_name(path), path)
    module_index["infiltratorfs"] = infil_module
    builtin = set()
    for line in config.splitlines():
        if line.startswith("CONFIG_") and line.endswith("=y"):
            builtin.add(line[7:-2])
    resolved: set[str] = set()
    loading: set[str] = set()
    order: list[tuple[str, bytes]] = []

    def needs(name: str) -> None:
        name = name.replace("-", "_")
        if name in resolved:
            return
        if name in loading:
            raise ValueError(f"Kernel module dependency cycle: {name}")
        path = module_index.get(name)
        if path is None:
            # An absent .ko is acceptable only when its driver is built in.
            symbol = {"virtio_pci": "VIRTIO_PCI", "virtio_blk": "VIRTIO_BLK"}.get(name)
            if symbol and symbol in builtin:
                resolved.add(name)
                return
            raise ValueError(f"Missing required native module: {name}")
        loading.add(name)
        vermagic = cmd_out("modinfo", "-F", "vermagic", path).split()[0]
        if vermagic != kernel_release:
            raise ValueError(f"Wrong module ABI for {path}: {vermagic}, need {kernel_release}")
        deps = cmd_out("modinfo", "-F", "depends", path)
        for dep in (x.strip() for x in deps.split(",")):
            if dep:
                needs(dep)
        order.append((name, module_data(path)))
        resolved.add(name)
        loading.remove(name)

    needs("virtio_pci")
    needs("virtio_blk")
    needs("infiltratorfs")
    return order


def make_initramfs(busybox: Path, modules: list[tuple[str, bytes]],
                   release: str, destination: Path) -> None:
    module_commands = "\n".join(
        f'/bin/busybox insmod /modules/{name}.ko || fail "MODULE_{name}"'
        for name, _ in modules
    )
    script = f"""#!/bin/sh
export PATH=/bin:/sbin
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev
fail() {{
  /bin/busybox echo "INFS_THREE_WAY_FAIL:$1" >/dev/console
  /bin/busybox poweroff -f
  /bin/busybox sleep 20
  exit 1
}}
/bin/busybox echo "INFS_INITRAMFS_ENTER" >/dev/console
actual=$(/bin/busybox uname -r)
[ "$actual" = "{release}" ] || fail "KERNEL_RELEASE_$actual"
/bin/busybox echo "INFS_REAL_KERNEL_PASS" >/dev/console
{module_commands}
/bin/busybox echo "INFS_KERNEL_MODULE_LOAD_PASS" >/dev/console
/bin/busybox mkdir -p /rootfs
/bin/busybox mdev -s || :
/bin/busybox sleep 2
mounted=0
for dev in /dev/vdb /dev/vda /dev/sdb /dev/sda; do
  if [ -b "$dev" ] && /bin/busybox mount -t infiltratorfs -o rw "$dev" /rootfs; then
    if [ -f /rootfs/System/Boot/source-identity.txt ]; then
      mounted=1
      break
    fi
    /bin/busybox umount /rootfs || :
  fi
done
[ "$mounted" = 1 ] || fail "INTRAFS_MOUNT"
[ "$(/bin/busybox cat /rootfs/System/Boot/source-identity.txt)" = "INFS_BOOT_DISK_EXCLUSIVE" ] || fail "SOURCE_IDENTITY"
/bin/busybox echo "INFS_NATIVE_MOUNT_READ_PASS" >/dev/console
/bin/busybox echo "guest-wrote-through-infiltratorfs" >/rootfs/System/Boot/guest-write.txt || fail "WRITE"
/bin/busybox sync
[ "$(/bin/busybox cat /rootfs/System/Boot/guest-write.txt)" = "guest-wrote-through-infiltratorfs" ] || fail "VERIFY_WRITE"
/bin/busybox echo "INFS_NATIVE_WRITE_PASS" >/dev/console
/bin/busybox umount /rootfs || fail "UNMOUNT"
/bin/busybox echo "INFS_BOOT_KERNEL_FILESYSTEM_PASS" >/dev/console
/bin/busybox poweroff -f
/bin/busybox sleep 20
"""
    payload = b"".join(cpio(name, stat.S_IFDIR | 0o755) for name in
                       ("bin", "dev", "proc", "sys", "modules", "rootfs"))
    payload += cpio("dev/console", stat.S_IFCHR | 0o600, major=5, minor=1)
    payload += cpio("bin/busybox", stat.S_IFREG | 0o755, busybox.read_bytes())
    payload += cpio("bin/sh", stat.S_IFLNK | 0o777, b"busybox")
    payload += cpio("init", stat.S_IFREG | 0o755, script.encode())
    for name, content in modules:
        payload += cpio(f"modules/{name}.ko", stat.S_IFREG | 0o644, content)
    payload += cpio("TRAILER!!!", 0)
    destination.write_bytes(gzip.compress(payload, compresslevel=6, mtime=0))


def boot_once(args: argparse.Namespace, esp: Path, image: Path, work: Path) -> None:
    code = args.ovmf / "OVMF_CODE_4M.fd"
    vars_template = args.ovmf / "OVMF_VARS_4M.fd"
    if not code.is_file():
        code = args.ovmf / "OVMF_CODE.fd"
        vars_template = args.ovmf / "OVMF_VARS.fd"
    require(code)
    require(vars_template)
    vars_copy = work / "OVMF_VARS.fd"
    shutil.copyfile(vars_template, vars_copy)
    serial = work / "serial.log"
    command = [
        "qemu-system-x86_64", "-machine", "q35,accel=tcg",
        "-cpu", "max", "-m", "2048", "-smp", "2",
        "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
        "-drive", f"if=pflash,format=raw,file={vars_copy}",
        "-drive", f"if=virtio,format=raw,file={esp}",
        "-drive", f"if=virtio,format=raw,file={image}",
        "-nographic", "-serial", f"file:{serial}",
        "-monitor", "none", "-no-reboot", "-net", "none",
    ]
    with (work / "qemu-console.log").open("wb") as console:
        try:
            subprocess.run(command, stdout=console, stderr=subprocess.STDOUT,
                           timeout=args.timeout, check=False)
        except subprocess.TimeoutExpired:
            # A completed guest marker is authoritative even if firmware did
            # not shut down QEMU on the first ACPI poweroff request.
            pass
    log = serial.read_text(errors="replace") if serial.exists() else ""
    print(log[-16000:])
    required = (
        "INFS_INITRAMFS_ENTER",
        "INFS_REAL_KERNEL_PASS",
        "INFS_KERNEL_MODULE_LOAD_PASS",
        "INFS_NATIVE_MOUNT_READ_PASS",
        "INFS_NATIVE_WRITE_PASS",
        "INFS_BOOT_KERNEL_FILESYSTEM_PASS",
    )
    missing = [value for value in required if value not in log]
    if missing:
        raise RuntimeError("Three-way Boot/InfiltratorFS/Kernel trial failed; "
                           f"missing {missing}. Evidence: {work}")
    print("PASS: Boot loaded the real InfiltratorOS kernel and initramfs "
          "from InfiltratorFS; its matching .ko mounted/read/wrote that volume.")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("boot", "driver", "kernel", "module", "module-root",
                 "kernel-config", "busybox", "mkfs", "fs-tool", "output"):
        p.add_argument("--" + name, type=Path, required=True)
    p.add_argument("--ovmf", type=Path, default=Path("/usr/share/OVMF"))
    p.add_argument("--timeout", type=int, default=300)
    args = p.parse_args()
    for name in ("boot", "driver", "kernel", "module", "kernel_config", "busybox",
                 "mkfs", "fs_tool"):
        setattr(args, name, require(getattr(args, name)))
    args.module_root = args.module_root.resolve(strict=True)
    if not args.module_root.is_dir():
        raise ValueError("Missing compiled native kernel module directory")
    release = "0.1.0-infiltrator"
    if cmd_out("modinfo", "-F", "vermagic", args.module).split()[0] != release:
        raise ValueError("InfiltratorFS .ko was not compiled against the InfiltratorOS kernel")
    work = args.output.resolve()
    work.mkdir(parents=True, exist_ok=True)
    if any(work.iterdir()):
        raise ValueError(f"Refusing to overwrite existing test workspace: {work}")
    initrd = work / "initrd.img"
    modules = modules_for_vm(args.module_root, args.module, release, args.kernel_config)
    make_initramfs(args.busybox, modules, release, initrd)
    image = work / "infiltratorfs.raw"
    esp = work / "esp.img"
    with image.open("wb") as handle:
        handle.truncate(512 * 1024 * 1024)
    with esp.open("wb") as handle:
        handle.truncate(96 * 1024 * 1024)
    run(args.mkfs, "--force", "-L", "INFILTEST", image)
    for directory in ("/System", "/System/Kernel", "/System/Kernel/Images",
                      "/System/Boot", "/boot"):
        run(args.fs_tool, image, "mkdir", directory)
    run(args.fs_tool, image, "put", args.kernel,
        "/System/Kernel/Images/InfiltratorOS-0.1.0.img")
    run(args.fs_tool, image, "put", initrd, "/boot/initrd.img")
    marker = work / "source-identity.txt"
    marker.write_text("INFS_BOOT_DISK_EXCLUSIVE\n")
    run(args.fs_tool, image, "put", marker, "/System/Boot/source-identity.txt")
    run(args.fs_tool, image, "ls", "/System/Kernel/Images")
    run("mkfs.fat", "-F", "32", "-I", "-n", "BOOTESP", esp)
    run("mmd", "-i", esp, "::/EFI", "::/EFI/BOOT", "::/EFI/BOOT/drivers_x64")
    run("mcopy", "-i", esp, args.boot, "::/EFI/BOOT/BOOTX64.EFI")
    run("mcopy", "-i", esp, args.driver,
        "::/EFI/BOOT/drivers_x64/InfiltratorFS_x64.efi")
    config = work / "boot.conf"
    config.write_text(r"""timeout 1
textonly true
use_nvram false
driver_diagnostics true
scanfor manual
showtools shutdown
menuentry "InfiltratorFS native kernel trial" {
    volume INFILTEST
    loader \System\Kernel\Images\InfiltratorOS-0.1.0.img
    initrd \boot\initrd.img
    linux_load memory
    ostype Linux
    graphics off
    options "console=ttyS0,115200 rdinit=/init panic=-1"
}
""")
    run("mcopy", "-i", esp, config, "::/EFI/BOOT/boot.conf")
    # Explicitly no kernel or initrd is copied to the FAT32 ESP; the EFI
    # filesystem driver must discover and read them from InfiltratorFS.
    manifest = work / "trial-inputs.sha256"
    manifest.write_text("".join(
        f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p}\n"
        for p in (args.boot, args.driver, args.kernel, args.module,
                  initrd, config, marker)
    ))
    boot_once(args, esp, image, work)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"THREE-WAY TRIAL: FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
