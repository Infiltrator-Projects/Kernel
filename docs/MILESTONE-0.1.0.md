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

## Correct native kernel version and public downloader

**Current product:** InfiltratorOS Kernel **0.1.0**. The imported Ubuntu
Linux source tree retains its upstream `Makefile` version **7.0.14**
for Linux code compatibility, but **7.0.14 is not an InfiltratorOS
release number**. The old first native builds incorrectly generated
`7.0.14-infiltrator` as their kernel release and module ABI.

**Corrected first-party native GitHub builder (not yet fully compiled
on the test machine):**

- Explicit Kbuild `KERNELRELEASE=0.1.0-infiltrator`, rather than
  appending `-infiltrator` to the upstream version. Both
  `include/config/kernel.release` and
  `include/generated/utsrelease.h` must contain this exact release.
- All new native image, headers and debug Debian packages must carry
  `X-InfiltratorOS-Module-ABI: 0.1.0-infiltrator`. The native
  `mkdebian`, `builddeb`, staging and installation code reject
  newly compiled products identifying themselves as 7.0.14.
- Debian **`0.1.0-3`** differentiates this kernel-version correction
  from the original `0.1.0-1` (wrong install paths) and
  `0.1.0-2` (corrected directories but inherited upstream ABI).
  These are Debian package revisions, **not InfiltratorOS versions**.

The public `InfiltratorOS-Kernel-0.1.0-amd64.run` is intentionally a
small **network downloader**. It contains the exact release commit ID and
download/build/install logic, **not an embedded 161 MB kernel source
archive**. GitHub only publishes this small file; the kernel is
compiled and tested on the computer executing the `.run`.

The `.run` automatically provisions missing folders including
`/Temporary/InfiltratorOS/Kernel` (requesting scoped sudo if
`/Temporary` itself is absent) and downloads the committed source
inside a new `Build/InfiltratorOS-Run.<unique>/Source` directory.
It compiles into a new `obj` tree on that computer, verifies native
packages and checksums, then installs the versioned files under
`/System/Kernel` without touching the existing Linux `/boot`
or EFI bootloader. Its `--build-only` mode skips native installation.

**Evidence boundary:** The previous user laptop build showed live
compilation and Debian `0.1.0-2` packaging but still printed
`7.0.14-infiltrator`. A **fresh recompilation from the newly
published corrected `.run`** is required to verify that the complete
compiled kernel, signed modules, module ABI and resulting .debs use
`0.1.0-infiltrator`. Source checks alone do not prove this happened.
If `/System/Kernel` already has the previous versioned files, the
installer refuses to overwrite them rather than silently replace an
existing native installation.

The user does **not** need `~/Kernel` or individual Git clone/build
commands. The authoritative implementation and release generator live
on GitHub `main`. The former `0.1.0-1` build and successful QEMU
handoff are historical evidence only, not the current release's
compiled ABI.

## Required preservation rules

- The imported Linux 7.0.14 source provenance, licensing and internal
  Linux API version must remain accurate. **Do not label 7.0.14 as an
  InfiltratorOS kernel version**; the native UTS release and compiled
  module ABI are **0.1.0-infiltrator**.
- Temporary checkout/build files remain under
  `/Temporary/InfiltratorOS/Kernel`, not `~/Kernel`; installed files
  remain exclusively under `/System/Kernel`.
- Do not modify the host's running Mint kernel, `/boot`, EFI or NVRAM
  as a side effect of the local compile or native file installation.
- Do not claim complete verification without a **real laptop build**
  showing a successful complete compilation, native packaging and
  installation. Prior `0.1.0-1` and `0.1.0-2` evidence is
  historical, not proof of new `0.1.0-3` binaries.

**For future development:** Work directly against GitHub `main`.
The public small `.run` downloads that commit and performs the
actual compiler test on the user's machine. No permanent local
patches, manual `~/Kernel` checkouts or GitHub kernel compilation
substitutes.

