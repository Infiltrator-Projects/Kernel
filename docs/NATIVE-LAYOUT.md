# InfiltratorOS Kernel: native source and installed layout

## Source of truth

The **Kernel** Git repository holds the complete source tree at its root.
The original Linux Kbuild directories (such as `arch/`, `drivers/`,
`kernel/`, `include/`, `mm/` and `fs/`) remain in place while they are
required to build the kernel. The product name and native installed namespace
are **InfiltratorOS**. Do not bulk-rename internal kernel symbols, filesystem
paths, ABI names or original copyright/licence records: Linux-origin names may
remain required for functional or legal reasons until individually migrated.

## Architecture goal: InfiltratorOS, with Linux compatibility

**InfiltratorOS is intended to become an independently engineered operating
system with its own kernel identity, release numbering, build and installation
structure. Linux compatibility is a supported interface, not the identity
or long-term architectural authority of InfiltratorOS.**

- The **current stage** is a fork of Linux/Ubuntu kernel source. It remains a
  Linux-derived implementation and retains original copyright, licence and
  provenance obligations. Do not represent it as independently implemented.
- The **destination** is an InfiltratorOS-owned kernel with its own kernel
  release identity and native `/System/Kernel` layout, progressively replacing
  inherited mechanisms. Linux interoperability is maintained through
  deliberately implemented, qualified compatibility interfaces such as
  system calls, ELF loading and relevant Linux UAPI behaviours.
- **`7.0.14-infiltrator` is transitional**: it is an exact kernel/module ABI
  identifier inherited from the current source, not the InfiltratorOS product
  version or permanent required kernel version scheme. A native ABI numbering
  scheme must be tested with kernel, modules, loader, Boot and Setup before
  replacement.
- Linux **application** compatibility does not automatically guarantee that
  arbitrary Linux `.ko` drivers are binary compatible. Module interoperability
  is a separate engineering and qualification concern.
- Linux-origin API names and licence/provenance notices can be retained where
  required. This does not imply the finished OS must identify as Linux.

## Version identities and transition

Keep these identities separate:

- **InfiltratorOS** has its own release version in the separate
  `Infiltrator-Projects/InfiltratorOS/VERSION` (currently `1.0.65`).
  That number describes the operating-system integration release, **not**
  the independently versioned Kernel component.
- **InfiltratorOS Kernel** has its own release version in this repository's
  root `VERSION` (currently `0.1.0`). This is the **product-facing
  component version** used by the native `.run` and the intended final
  Debian kernel package version.
- **Upstream source and ABI** remain independent: the imported Ubuntu HWE
  source currently reports Linux `7.0.14`; its distinct test kernel ABI is
  `7.0.14-infiltrator`. These identify inherited low-level kernel
  compatibility, module vermagic and dependency paths, and are not the
  InfiltratorOS Kernel product release number.

**Future packaging contract (not implemented yet):** the visible package
family should use `infiltratoros-kernel`, with corresponding native headers
and debug packages. Debian `Version` should derive from this repository's
`VERSION`, with an appropriate package revision. The underlying kernel ABI
must remain accessible in packaging metadata and wherever the actual module
loader or early boot paths require it. Merely renaming a generated Debian
package filename would leave its internal `Package` identity, dependency
wiring and install paths wrong.

The inherited Kbuild packaging currently emits `linux-image-7.0.14-infiltrator`
and companion packages. They are an **engineering baseline**, not the desired
final product identity. Do not change generated packaging or kernel ABI inputs
during an active compilation; migrate and qualify the package generator,
header/debug links, native installer, Boot and Setup as one subsequent change.

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
