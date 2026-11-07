# InfiltratorOS Kernel: native source and installed layout

## Source of truth

The **Kernel** Git repository holds the complete source tree at its root.
The original Linux Kbuild directories (such as `arch/`, `drivers/`,
`kernel/`, `include/`, `mm/` and `fs/`) remain in place while they are
required to build the kernel. The product name and native installed namespace
are **InfiltratorOS**. Do not bulk-rename internal kernel symbols, filesystem
paths, ABI names or original copyright/licence records: Linux-origin names may
remain required for functional or legal reasons until individually migrated.

## Native artifact layout

This follows the existing InfiltratorOS authority:
`Infiltrator-Projects/InfiltratorOS/docs/FILESYSTEM.md`.

```text
/System/Kernel/
├── Images/
│   ├── InfiltratorOS-<release>.img
│   ├── InfiltratorOS-<release>.config
│   └── InfiltratorOS-<release>.map  (when available)
├── Modules/
│   └── <release>/
│       └── kernel/.../*.ko
├── Filesystems/
│   └── <format>.ko                 (owned by Filesystem-*; not this package)
└── Firmware/
    └── ...                         (only verified firmware from its owner)
```

The `Modules/<release>/` hierarchy keeps module ABI identity and dependency
relationships intact. The `Filesystems/` namespace is reserved for the
individual filesystem-provider builds and is not populated by copying every
upstream Linux filesystem module there. EFI BOOT binaries and firmware-stage
drivers belong to the independent **Boot** component, not this repository.

The transitional kernel image and modules currently retain Linux ABI
dependencies. Their native staging paths are **not yet a usable replacement
for `/boot` and `/lib/modules`**: the runtime loader, initramfs, module
dependency maps, UEFI handoff, signing, rollback and recovery still need to
be integrated and verified. No staging operation claims a bootable installation.

## Native builder and staging

On Mint or Debian, after the full source compilation succeeds:

```bash
make build-only SKIP_DEPS=1
make stage-native
```

`build-only` creates locally compiled Debian kernel packages in `dist/`;
`stage-native` unpacks **that locally compiled image package** and stages
the image and module hierarchy in `dist/native/System/Kernel/`, with
`SHA256SUMS.txt` and `STAGING-STATUS.txt`. It does not touch the live
`/System`, change the host's bootloader, or install packages.

```bash
make package-run
```

Creates `dist/InfiltratorOS-Kernel-<VERSION>-amd64.run`, a source-bearing,
self-extracting native builder assembled from the committed Git tree. On a
supported computer it extracts the source locally, detects that host's running
kernel and configuration, compiles with the local toolchain, produces its own
packages and stages its `/System/Kernel` hierarchy.

The `.run` intentionally **does not yet install or activate** the image:
until Boot and Setup qualify the kernel-runtime transition, installation
would be misleading and unsafe. No binary from a central CI runner is silently
described as a native compilation.

## Identity and licensing

Keep the existing Linux, Ubuntu and other contributor attribution/licence
records in place. The locally built product and user-facing file names use
InfiltratorOS. Actual internal renaming is an incremental engineering task
requiring driver, module, binary interface and boot verification, not a
global string substitution.
