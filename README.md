# InfiltratorOS Kernel

**Development handoff / current build status:** [docs/BUILD-STATUS.md](docs/BUILD-STATUS.md). It records the original source identity, local Mint test baseline, unresolved build blockers, and exact recovery commands. This is not a qualified bootable release.

This repository contains the **complete Ubuntu Linux HWE 7.0 kernel source**
used as the initial InfiltratorOS kernel baseline. It is maintained directly
in the repository root, not inside a subdirectory or as a download-only wrapper.

Initial source: Ubuntu linux-hwe-7.0 7.0.0-42.42~24.04.1, including the
distribution's source patch set. See [baseline provenance](docs/upstream/BASELINE.md).
The original Linux kernel COPYING and LICENSES/ notices remain applicable.

**Current status:** The Linux-derived kernel baseline has **successfully
compiled and produced three Debian kernel packages on Linux Mint 22.3**, and
its compiled image/modules were successfully staged under the InfiltratorOS
`/System/Kernel` native artifact hierarchy on 2026-11-07. The original build
artifacts are preserved on the test machine. It has **not** been installed,
boot-tested or independently reimplemented. InfiltratorOS is intended to
evolve into a distinct operating system and kernel with Linux compatibility,
rather than permanently remaining a renamed Linux distribution.

Boot is maintained in Infiltrator-Projects/Boot. Format-specific filesystem
engines remain owned by their independent Filesystem-* repositories.

## Native builder

- `make probe` checks the host and installed source configuration.
- `make configure-only` configures an out-of-tree build using Mint/Debian defaults.
- `make build-only` compiles InfiltratorOS-versioned Debian image, headers and debug packages, without installation. The embedded module ABI remains transitional.
- `make check` checks the first-party build script syntax and contract (not the kernel).

The first-party scripts use APT build dependencies on Debian/Linux Mint
and need the appropriate deb-src entries. They do not change the running
kernel or boot configuration. The first-party builder is
`scripts/build-native.sh`. The Linux kernel's normal Kbuild targets
remain available.

- `make stage-native` stages compiled image and modules under a versioned `dist/native-<VERSION>/System/Kernel/`, preserving the original successful `dist/native/` baseline.
- `make package-run` produces a source-bearing local native `.run` builder in `dist/` (not published automatically).

[Native InfiltratorOS Kernel source and installed-file contract](docs/NATIVE-LAYOUT.md) specifies the `/System/Kernel/{Images,Modules,Filesystems,Firmware}` layout. Staging and `.run` compilation do **not** install or boot a kernel; Boot/Setup integration is still outstanding.
