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
- The **actual existing 0.1.0 Debian packages retain conventional Linux installation paths** (e.g. `/boot`, `/lib/modules`, `/usr/src`). The native `/System/Kernel/{Images,Modules,Filesystems,Firmware}` **staging** hierarchy is correct, but native **package deployment** is not finished.
- The generic kernel adapter to consume the independent canonical filesystem `.so` is not implemented/qualified; transitional `.ko` modules are not final native filesystem support.
- **Off-machine binary backup is NOT confirmed.** Both original artifacts and their verified archive are on the Latitude 5550's storage. GitHub holds the source and evidence, not those large `.deb` packages or virtual disk images.

## Next action — protect the actual binaries

**Do not compile or clean anything.** Identify an independently mounted removable disk or remote filesystem:

```bash
lsblk -o NAME,TRAN,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS
```

Once the correct external mount is positively identified, copy **the entire**
`~/InfiltratorOS-Kernel-Archive/` tree to it *without moving, deleting or
overwriting existing files*, and check the copied
`InfiltratorOS-Kernel-0.1.0/SHA256SUMS-Archive.txt` and
`HistoricalHomeOutputs-0.1.0/SHA256SUMS.txt` (and its
`UpstreamRemainder/SHA256SUMS.txt`) on the destination. A same-disk copy is
not off-device protection. Never guess a device path or format/mount/modify a
drive while choosing the backup target.

**After off-machine backup:** Work on isolated QEMU runtime module-loading and read/write root-filesystem qualification, then separately design/verify native package and Setup installation paths. Keep the proved 0.1.0 baseline immutable. Future development work should be on the same `main` branch and use new versioned artifacts and disposable `/Temporary/InfiltratorOS/` work areas.

## Required preservation rules

- No `make clean`, `git clean`, source tree deletion, silent in-place rebuild, installer execution, bulk rename, existing archive overwrite, reboot, host kernel installation or EFI/NVRAM modifications.
- Linux internal `7.0.14-infiltrator` `vermagic` and package references must not be renamed to `0.1.0` without real module-ABI work; present `0.1.0` as the *product* version.
- Project-specific native user-facing paths use capitalised full names. Temporary staging belongs under `/Temporary/InfiltratorOS`; permanent kernel assets under `/System/Kernel`; independent shared filesystem engines under `/System/Filesystems`.
- Never claim completed stages from CI checks alone. Real on-laptop success evidence is documented in [the complete build and qualification log](BUILD-STATUS.md).

**For a future conversation:** Open this file and the full `docs/BUILD-STATUS.md` before editing anything. Resume at off-machine binary backup; then pursue isolated QEMU module/root qualification. All earlier build, virtual-boot and home-cleanup steps are already complete.
