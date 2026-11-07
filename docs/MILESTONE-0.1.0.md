# InfiltratorOS Kernel 0.1.0 — verified milestone, START HERE

**Date of evidence:** 2026-11-07 (Australia/Melbourne).
**Repository:** `Infiltrator-Projects/Kernel`; authoritative development branch: `main`.
**Product version:** `0.1.0`. **Compiled compatibility ABI:** `7.0.14-infiltrator`.
This is a Linux-derived transitional kernel, not yet an independently implemented InfiltratorOS kernel.

## What is already achieved (DO NOT repeat)

1. **Kernel compiled successfully**, more than once, on Shannon's Linux Mint Latitude 5550. Three InfiltratorOS 0.1.0 Debian packages were built: image, headers and debug. The original historic in-source build objects and `~/Kernel/dist/` remain preserved.
2. **Native-layout staging succeeded**, without installation, under
   `/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-0.1.0/System/Kernel/`.
   The staged image/modules passed `SHA256SUMS.txt` verification. The `Filesystems/` and `Firmware/` staging subdirectories are reserved but not populated.
3. **Real virtual boot succeeded**. QEMU/OVMF, verified Boot v0.1.39, and the canonical `/System/Filesystems/FAT16.so` loaded the exact compiled kernel. The kernel reached a test initramfs. The real machine printed
   `BOOT-FAT16-SO-LINUX-HANDOFF-PASS` and
   `InfiltratorOS OVMF: PASS: staged InfiltratorOS Kernel 0.1.0 booted to the VM test initramfs`.
4. **First binary milestone archived and checksum-verified**, with original packages, staged kernel, test disks, logs and checksum manifest:
   `/home/ssmith/InfiltratorOS-Kernel-Archive/InfiltratorOS-Kernel-0.1.0/`.
   The original build and test files are preserved as well. Do **not** repeat `preserve-milestone.sh`: its overwrite refusal is intentional.
5. **Home-directory packaging debris corrected**. Eight confirmed Debian artifacts were moved, with checksum verification, to
   `/home/ssmith/InfiltratorOS-Kernel-Archive/HistoricalHomeOutputs-0.1.0/`.
   Three more source-matched upstream files were moved and verified in
   `.../HistoricalHomeOutputs-0.1.0/UpstreamRemainder/`.
   This closes **all 11 identified loose kernel packaging files**; do not run the relocation again.
6. **Source, build-status history, regression scripts and this handoff reside on GitHub's `main` branch**. Never confuse GitHub source preservation with binary asset preservation.

## What has NOT been achieved

- No successful **full installed InfiltratorOS system boot**; the physical Mint laptop's running kernel, EFI partition, NVRAM and boot order were not changed.
- No qualification yet for **runtime kernel module loading**, a **read/write root filesystem**, physical hardware driver selection, Secure Boot or a recovery-capable OS installation.
- The **historical 0.1.0-1 Debian binaries retain Linux installation paths** (`/boot`, `/lib/modules`, `/usr/src`). The GitHub native package generator is now corrected for **0.1.0-2** to use only `/System/Kernel/{Images,Modules,Filesystems,Firmware,Headers,Debug}`. A no-recompile archive-to-native repacker and synthetic tests have been added. The actual native **0.1.0-2 package set has not yet been generated and checked on Shannon's laptop**, nor have native module loading and Boot/Setup installation been qualified.
- The generic kernel adapter to consume the independent canonical filesystem `.so` is not implemented/qualified; transitional `.ko` modules are not final native filesystem support.
- **Off-machine binary backup is NOT confirmed.** Both original artifacts and their verified archive are on the Latitude 5550's storage. GitHub holds the source and evidence, not those large `.deb` packages or virtual disk images.

## Backup target inventory — 2026-11-07 (read-only host evidence)

Shannon ran `lsblk -o NAME,TRAN,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS`
on the Mint Latitude 5550. The machine currently reports:

- `mmcblk0` 119.1G, `TRAN=mmc`, with 21 test-format partitions
  (including FAT, exFAT, NTFS, EXT2/3/4, Btrfs, HFS, ZFS and APFS).
  **Do not touch** as a backup target; it is filesystem-test media.
- `nvme0n1` 1.9T main internal drive: mounted ext4 root
  `nvme0n1p2` (800G), `/boot/efi` (512M), swap, and the
  `nvme0n1p5` 1T `infiltratorfs` partition. Never format,
  mount or write the filesystem-test partition as a backup shortcut.
  The golden archives currently live on this machine's storage.
- `nvme1n1` 238.5G **separate NVMe**, principally an unmounted
  `nvme1n1p2` 237.6G NTFS partition plus existing auxiliary
  partitions. No evidence it is empty or authorized for use.
  **Do not mount read-write, write, partition or format** until its
  ownership and contents are confirmed.
- The inventory shows **no clearly connected USB storage or mounted
  external destination**. Network mounts were not assessed by this
  command; no off-machine backup has been proven.

**Off-machine backup is optional** for continuing this development. Both
the original and copied binaries are on the same laptop, but GitHub
independently retains the full source and validated development history.
No USB drive, new OS installation or recompilation is required to correct
the Debian package paths.

## NEXT ACTION — repair the previously compiled native kernel packages

The original Linux-path `0.1.0-1` packages and their successful QEMU boot
are immutable evidence. The **corrected GitHub source** now generates native
`0.1.0-2` packages, with no payload under `/boot`, `/lib/modules`,
`/usr/src` or `/usr/lib/debug`. The image and module payloads go to
`/System/Kernel/Images/` and `/System/Kernel/Modules/`. Compiled developer
headers and debug symbols go to `/System/Kernel/Headers/` and `/System/Kernel/Debug/`.
These optional developer folders are documented in the OS-wide
`InfiltratorOS/docs/FILESYSTEM.md` contract.

**Next real laptop command, not yet executed:**

```bash
cd ~/Kernel && git pull --ff-only && bash scripts/infiltrator/repackage-native.sh
```

This uses the already verified binary snapshot, extracts the existing
compiled image/modules/headers/debug, packages them in new **separate**
`/Temporary/InfiltratorOS/Kernel/Packages/NativeLayout/InfiltratorOS-0.1.0/`
files at Debian revision `0.1.0-2`, validates that **each** actual Debian
archive contains only `/System/Kernel/` installation paths, records the exact
transitional ABI and generates an independent SHA-256 manifest.

It neither rebuilds the kernel nor runs `dpkg -i`, `apt install`, host
kernel replacement, EFI modification, reboot or removal of the historical
`0.1.0-1` package archives. An existing completed native `0.1.0-2` output
is never overwritten. Only after this produces a **real on-laptop PASS**
may we claim corrected native 0.1.0 binary packages have been produced.

**After repackaging:** perform a disposable VM test against the actual
native package payload and qualify runtime module loading and a read/write
root filesystem. The corrected path and package metadata alone do **not**
make a fully installed, bootable InfiltratorOS distribution.


## Required preservation rules

- No `make clean`, `git clean`, source tree deletion, silent in-place rebuild, installer execution, bulk rename, existing archive overwrite, reboot, host kernel installation or EFI/NVRAM modifications.
- Linux internal `7.0.14-infiltrator` `vermagic` and package references must not be renamed to `0.1.0` without real module-ABI work; present `0.1.0` as the *product* version.
- Project-specific native user-facing paths use capitalised full names. Temporary staging belongs under `/Temporary/InfiltratorOS`; permanent kernel assets under `/System/Kernel`; independent shared filesystem engines under `/System/Filesystems`.
- Never claim completed stages from CI checks alone. Real on-laptop success evidence is documented in [the complete build and qualification log](BUILD-STATUS.md).

**For a future conversation:** Open this file and the full `docs/BUILD-STATUS.md` before editing anything. Resume at **actual native 0.1.0-2 repackaging** using the above command; then qualify native package payloads, isolated QEMU module/root operation and Boot/Setup installation. Off-device backup is optional and not an installation prerequisite. All earlier build, virtual-boot and home-cleanup steps are already complete.
