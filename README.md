# InfiltratorOS Kernel

**START HERE — verified 0.1.0 milestone, preserved files and next action:** [docs/MILESTONE-0.1.0.md](docs/MILESTONE-0.1.0.md).

**Development handoff / current build status:** [docs/BUILD-STATUS.md](docs/BUILD-STATUS.md). It records the original source identity, local Mint test baseline, unresolved build blockers, and exact recovery commands. This is not a qualified bootable release.

This repository contains the **complete Ubuntu Linux HWE 7.0 kernel source**
used as the initial InfiltratorOS kernel baseline. It is maintained directly
in the repository root, not inside a subdirectory or as a download-only wrapper.

Initial source: Ubuntu linux-hwe-7.0 7.0.0-42.42~24.04.1, including the
distribution's source patch set. See [baseline provenance](docs/upstream/BASELINE.md).
The original Linux kernel COPYING and LICENSES/ notices remain applicable.

**Current status (2026-11-07):** The Linux-derived kernel baseline has
**successfully compiled and produced three InfiltratorOS Kernel 0.1.0 Debian
packages on Linux Mint 22.3**. Their locally built kernel image and modules
were staged at
`/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-0.1.0/System/Kernel/`
and passed a read-only SHA-256 verification. **The exact staged kernel
successfully booted in QEMU/OVMF**, using Boot `0.1.39` and the canonical
`FAT16.so`, and reached a guest test-initramfs marker. The complete
evidence and commands are in [docs/BUILD-STATUS.md](docs/BUILD-STATUS.md).
The image has **not** been installed or booted as the laptop's host kernel,
and full root-filesystem/module loading, Secure Boot, hardware qualification
and independence from the transitional Linux ABI are **not** established.
InfiltratorOS is intended to evolve into a distinct operating system and
kernel with Linux compatibility, rather than permanently remaining a
renamed Linux distribution.

Boot is maintained in Infiltrator-Projects/Boot. Format-specific filesystem
engines remain owned by their independent Filesystem-* repositories.

## Native builder

- `make probe` checks the host and installed source configuration.
- `make configure-only` configures an out-of-tree build using Mint/Debian defaults.
- `make build-only` compiles InfiltratorOS-versioned Debian image, headers and debug packages, without installation. The embedded module ABI remains transitional.
- `make check` checks the first-party build script syntax and contract (not the kernel).

Native **uninstalled** build outputs are under `/Temporary/InfiltratorOS/Kernel/`:
`Build/` for new object-tree work, `Packages/` for locally built
artifacts, `Staging/InfiltratorOS-<VERSION>/System/Kernel/` for the
future installed layout, and `Logs/` for logs from the native runner.
The host's actual `/System/Kernel/` is reserved for a qualified installer,
never written by these commands. The historic `dist/` and in-source
compiler objects are preserved for the first proven baseline. Underlying
module vermagic remains a transitional Linux ABI; changing staged directory
names does not implement a new kernel ABI or loader.

The first-party scripts use APT build dependencies on Debian/Linux Mint
and need the appropriate deb-src entries. They do not change the running
kernel or boot configuration. The first-party builder is
`scripts/build-native.sh`. The Linux kernel's normal Kbuild targets
remain available.

- `make stage-native` stages the uninstalled kernel image and modules under `/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-<VERSION>/System/Kernel/`. The earlier `~/Kernel/dist/native/` compilation baseline is preserved unchanged.
- `make package-run` produces a source-bearing local native `.run` builder in `/Temporary/InfiltratorOS/Kernel/Packages/` (not published automatically).

## Preserve verified milestone outside Temporary

The confirmed `0.1.0` image actually booted in QEMU/OVMF, but the
compiled binary packages and virtual-machine evidence remain **on the
local host**, some under `/Temporary/InfiltratorOS/`. GitHub preserves
source and development history, not these binary files. Before beginning
the next development milestone, perform a separately verified, non-destructive
snapshot under the user's home directory:

```bash
cd ~/Kernel && git pull --ff-only
bash scripts/infiltrator/preserve-milestone.sh \
  --evidence /Temporary/InfiltratorOS/Kernel/Tests/InfiltratorOS-0.1.0-OVMF.n30ks8BD
```

The output directory is `~/InfiltratorOS-Kernel-Archive/InfiltratorOS-Kernel-0.1.0/`.
It retains the historical first-build `dist/` outputs, the actual three
InfiltratorOS Debian packages, the checksum-verified native
`System/Kernel/` staged tree, real Boot/OVMF test output including the
disposable media and serial log, any available full build logs, GitHub
source commit identification, and a new verified SHA-256 archive manifest.

**No live kernel, EFI partition, NVRAM, boot configuration or packaged source
is modified. No source files or original test evidence are removed or moved.**
The script refuses to overwrite an existing complete archive and retains an
incomplete archival attempt for inspection rather than deleting source files.
The user should confirm the **real host's** printed `PASS` before treating
the binary archival milestone as complete.

This creates a second local copy on the **same computer**, not an independent
off-device backup. The source is separately protected in GitHub; fully
protecting the compiled binary assets against physical disk failure requires
a second physical device or another remote destination.

## Corrected native Debian packages — no kernel rebuild required

**Important historical distinction:** The original successfully compiled
Kernel `0.1.0-1` packages used inherited Linux installation paths
(`/boot`, `/lib/modules`, `/usr/src`, `/usr/lib/debug`). Simply
copying their image/modules into native staging did not fix the actual Debian
package. These `-1` packages and their successful QEMU boot evidence remain
preserved and must **never** be overwritten or silently reinstalled.

The `scripts/package/builddeb` native mode now writes actual native
`0.1.0-2` package payloads exclusively under `/System/Kernel/`, with
image and modules in `Images/` and `Modules/`, optional development
headers in `Headers/`, and debug symbols in `Debug/`. These paths are
specified by the authoritative OS filesystem contract. The new native
packages have no inherited Debian `/etc/kernel` or `/usr/share/kernel`
post-install hooks.

**Use the original compiled binaries instead of rebuilding:**

```bash
cd ~/Kernel && git pull --ff-only && bash scripts/infiltrator/repackage-native.sh
```

This verifies the already archived first kernel image and original three
Debian packages, creates new `0.1.0-2` image/headers/debug packages under
`/Temporary/InfiltratorOS/Kernel/Packages/NativeLayout/InfiltratorOS-0.1.0/`,
inspects their **actual payload paths**, and generates a SHA-256 manifest.
The old `-1` files remain immutable; this does not compile, install,
modify Mint's boot configuration or boot the new package. The end-to-end
synthetic Debian tests are `tests/repackage-native.sh` and
`tests/native-builddeb-paths.sh`.

**This source fix is committed, but a successful real laptop repackaging
has not yet been observed.** A properly located Debian payload is a file
placement improvement, not proof that InfiltratorOS is fully bootable or
that its eventual kernel module loader and native Boot/Setup installer are
complete.

## Isolated UEFI handoff test — first successful run

The Mint Latitude 5550 has a checksum-verified native staged kernel
`0.1.0` image and confirmed `CONFIG_EFI=y`, `CONFIG_EFI_STUB=y`,
`CONFIG_BLK_DEV_INITRD=y`. Its installed Boot package is `0.1.38`,
while the published Boot `0.1.39` is independently testable without
installing anything.

The following non-privileged test **already passed** on the Latitude 5550;
it can be repeated if further qualification or regression testing is
required:

```bash
bash scripts/infiltrator/test-ovmf-handoff.sh
```

This verifies the existing staged image checksums, downloads and verifies
the **published Boot 0.1.39 .deb**, extracts its EFI executable into
`/Temporary/InfiltratorOS/Kernel/Tests/`, and runs Boot's **matching,
release-tagged** `tests/test_so_boot.py` with the machine's
`/System/Filesystems/FAT16.so`, a disposable FAT16 disk, synthetic
initramfs and OVMF/QEMU. A successful VM test must emit
`BOOT-FAT16-SO-LINUX-HANDOFF-PASS`, which means the guest reached a test
initramfs; this does **not** establish a fully installed or bootable
InfiltratorOS system. All test evidence and failures are retained under a
unique named directory in `/Temporary/InfiltratorOS/Kernel/Tests/`.

The wrapper **does not** run `apt install`, modify the ESP, NVRAM, live
`/System/Kernel`, `/boot`, or the running kernel. It leaves the user's
successfully compiled `~/Kernel/dist/` artifacts untouched.

[Native InfiltratorOS Kernel source and installed-file contract](docs/NATIVE-LAYOUT.md) specifies the `/System/Kernel/{Images,Modules,Filesystems,Firmware}` layout. Staging and `.run` compilation do **not** install or boot a kernel; Boot/Setup integration is still outstanding.
