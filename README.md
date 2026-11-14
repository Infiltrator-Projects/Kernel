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
- `make package-run` produces a small network-downloading `.run` under `/Temporary/InfiltratorOS/Kernel/Packages/`; GitHub Releases distributes the exact committed version.

## Install and compile from GitHub (native InfiltratorOS 0.1.0)

The **public .run download** is available from
[Kernel v0.1.0 Releases](https://github.com/Infiltrator-Projects/Kernel/releases/tag/v0.1.0).
The small executable contains a pinned public Git commit and download/build
logic; it **does not** embed the kernel source or require `~/Kernel`.
When launched on a compatible Linux machine, it downloads that exact
source commit, compiles with the **local** kernel toolchain in
`/Temporary/InfiltratorOS/Kernel/Build/`, creates and verifies native
Debian packages under `/Temporary/InfiltratorOS/Kernel/Packages/`,
and installs native files only under `/System/Kernel/`. The installer
automatically creates missing temporary folders. The lightweight release workflow only publishes the downloader; a separate
GitHub Actions integration workflow compiles the actual kernel and boots it
under QEMU/OVMF before claiming a verified native boot-chain result.

**Kernel identity:** InfiltratorOS Kernel **0.1.0** has the native
kernel release and compiled module ABI **`0.1.0-infiltrator`**,
not `7.0.14-infiltrator`. The source tree is based on Ubuntu/Linux
**7.0.14**, which remains unchanged internally for Linux API and code
compatibility. It is an upstream source version, **not** a historical
InfiltratorOS release. The first-party builder explicitly sets
`KERNELRELEASE=0.1.0-infiltrator` and verifies the generated UTS
release header before compiling. Native package generation rejects the
old `7.0.14-infiltrator` identity.

The corrected Debian package revision `0.1.0-3` introduced the independently
versioned ABI; the current **revision `0.1.0-4`** additionally supplies the
native module loader and firmware search integration. The historical `-1`
and `-2` packages retained wrong native paths or an inherited Linux version.
These are Debian packaging revisions, not separate InfiltratorOS kernel versions.
The normal GitHub `.run` automatically preserves and replaces existing
same-version 0.1.0 native files when present, without requiring command-line
options; the backups are retained under `/Temporary/InfiltratorOS/Kernel/Backups/`.

**Verification status:** A clean GitHub-hosted compile and real QEMU/OVMF
InfiltratorFS-to-Kernel boot have now passed using the native
`0.1.0-infiltrator` ABI. Physical hardware boot qualification is separate;
a VM success does not establish a deployed desktop operating system. The public
`.run` may also use `--build-only` to compile and verify without
installing. Production boot activation and complete installed root userspace are not yet
qualified; virtual-machine boot, native module loading and live InfiltratorFS
mount/read/write are qualified in the pinned two-boot trial. Existing host `/boot`, Linux
modules, EFI and NVRAM are not modified by the native installer.
Existing versioned native files are not silently overwritten. To repair a previously installed same-version 0.1.0 kernel with the inherited Linux ABI, run the current small `.run` with `--replace-existing`; the installer preserves the six previous versioned native kernel paths under `/Temporary/InfiltratorOS/Kernel/Backups/` and leaves independent filesystem providers untouched. The repair flag is explicit and not accepted together with `--build-only`.

See [the updated milestone and verification boundary](docs/MILESTONE-0.1.0.md)
and [native filesystem contract](docs/NATIVE-LAYOUT.md).

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

## Native kernel module discovery

The native kernel uses its versioned helper in
`/System/Kernel/Runtime/InfiltratorOS-<version>/modprobe` to load ordinary
hardware drivers from `/System/Kernel/Modules/InfiltratorOS-<version>/`.
Device discovery uses the installed InfiltratorOS udev rule, and the kernel
searches `/System/Kernel/Firmware` before the existing Linux firmware paths.
The helper refuses to load native drivers into the distribution kernel.

A VM test has exercised automatic driver loading from the native hierarchy;
physical hardware qualification is still required. Linux cannot directly load
a userspace filesystem `.so` as a kernel module. The V2 filesystem bridge for
Linux remains separate unfinished work.

## Three-component Boot → InfiltratorFS → Kernel qualification

The development workflow runs isolated QEMU/OVMF tests using disposable disk
images. One qualification boots the compiled kernel through a V2 filesystem
provider. An older persistence qualification uses an EFI filesystem driver and
kernel filesystem module; it does not establish a V2-only Linux storage path.
The public installer does not create a separate BOOT configuration or provide
a separate VM test launcher. Physical firmware and hardware remain unqualified.

## Verified two-boot native InfiltratorFS milestone — 8 November 2026

The [completed GitHub Actions qualification](https://github.com/Infiltrator-Projects/Kernel/actions/runs/42434204081)
compiled InfiltratorOS Kernel `0.1.0-infiltrator` and exercised the real
Boot `0.1.39` UEFI application and the source-owned Format 0.19
InfiltratorFS EFI reader. Boot and its filesystem driver lived on the
FAT32 ESP; both kernel and initramfs lived exclusively on InfiltratorFS.
The guest loaded the matching native `infiltratorfs.ko`, verified full-file
kernel/initramfs SHA-256 digests, mounted/read/wrote InfiltratorFS, and
shut down cleanly. A **second entirely separate QEMU boot** then mounted
the same disk, verified that the first boot's written file persisted and
rechecked the boot payloads and 1,257 canonical OS resources (23 fonts,
1,233 icons and one image) against source digests. Both serial logs and the
source inventory are attached as run evidence.

This is a tested native filesystem and kernel handoff in virtual firmware,
**not** a production installer, real machine EFI deployment, Secure Boot
qualification or a complete InfiltratorOS desktop userspace. Trial inputs
remain pinned and all test disks, firmware variable stores and generated
files are disposable.
