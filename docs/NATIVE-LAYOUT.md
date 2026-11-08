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

**Native packaging implementation (added after the first successful build):**
the first-party `make build-only` wrapper now opts into independently versioned
Debian package generation. The intended three binary packages are:

- `infiltratoros-kernel-image-0.1.0`
- `infiltratoros-kernel-headers-0.1.0`
- `infiltratoros-kernel-image-0.1.0-dbg`

The Debian source package is `infiltratoros-kernel` and the Debian package
version is `0.1.0-1`. The version comes from this repository's `VERSION`,
not Linux's `7.0.14`. Embedded binary compatibility remains tied to the
current transitional module release `7.0.14-infiltrator`, recorded as
`X-InfiltratorOS-Module-ABI` metadata. Kernel `/boot/vmlinuz-<ABI>`,
`/lib/modules/<ABI>` and `/usr/src/linux-headers-<ABI>` paths remain
transitional compatibility implementation details; they are **not** the
InfiltratorOS Kernel product version.

The generated package names are matched by Debian's image, debug and headers
build rules, not renamed after building. The original Linux Kbuild packaging
mode remains available when native opt-in is absent. **The first successful
Mint-host packages remain preserved under their original Linux names; this
new native product packaging mode has not yet had another full Mint-host
compilation/packaging qualification.** Its generator and staging contracts
are checked independently in CI. Do not erase or replace the successful
transitional binary baseline.

## Important: transitional staging is not the intended native kernel layout

The first compiled image and three Debian packages have been produced on the
Mint test machine, and a versioned source-first staging implementation exists.
**However, the present staged tree is only a transitional compatibility
artifact, not proof of the final InfiltratorOS kernel layout or runtime.**

The **preserved first staging** under `~/Kernel/dist/native` copies the
Linux `/lib/modules/<upstream-module-abi>/kernel/...` tree into the staged
`/System/Kernel/Modules/<upstream-module-abi>/kernel/...`. That was a
**mistake in the native product staging layout** and is preserved only as
evidence of the first successful compile.

**Corrected staging for subsequent builds** lives under
`/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-<VERSION>/System/Kernel/`.
Its native module directory is
`Modules/InfiltratorOS-<VERSION>/kernel/...`, not a directory named for the
Linux source version. The exact transitional kernel/module ABI remains in
`STAGING-STATUS.txt` and the package's `X-InfiltratorOS-Module-ABI`
field. **This is a naming and placement correction only**. The binaries
still contain inherited Linux vermagic, and the staged modules cannot
simply be installed into their new directory and expected to work with
Linux modprobe. Native module loading must be implemented and qualified.

The staging currently copies the whole distribution module set, not
machine-selected drivers, and includes inherited Linux filesystem modules.
These are compatibility inputs, **not** independent InfiltratorOS filesystem
engines. Do not present successful staging as evidence of a finished native
runtime or hardware-specific driver selection.

**The OS filesystem contract is owned by
[InfiltratorOS/docs/FILESYSTEM.md](https://github.com/Infiltrator-Projects/InfiltratorOS/blob/main/docs/FILESYSTEM.md)
and
[InfiltratorOS/docs/FILESYSTEM_SO_RUNTIME_CONTRACT.md](https://github.com/Infiltrator-Projects/InfiltratorOS/blob/main/docs/FILESYSTEM_SO_RUNTIME_CONTRACT.md):**
the final single per-format engine is an independently maintained `.so`
under `/System/Filesystems/`, shared conceptually among BOOT, OS kernel and
applications via a **future proven generic adapter/loader**. Format-specific
`.ko` under `/System/Kernel/Filesystems/` is a **transitional Linux adapter**,
not the end-state driver model. This Kernel repository must not take ownership
of the per-format filesystem engines, nor silently relocate inherited `.ko`
files into the independent provider namespace. A generic kernel bridge capable
of consuming the canonical format engine has **not** been implemented or
qualified. Kernel-space execution cannot simply load a normal userspace
`.so` without an appropriate architecture and privilege boundary.

Native completion requires hardware-appropriate module selection, independent
version/ABI identity, qualified Boot/Setup handoff, a working native
module loader, correct driver and filesystem provider ownership, and runtime
mount/boot tests. Until those milestones, call this **compatibility staging**,
not a final native filesystem layout. The previously verified compiled baseline and historical
`~/Kernel/dist/native/` tree must be preserved. No migration script deletes
or renames those existing artifacts or running host module paths.

## Native artifact layout

This follows the existing InfiltratorOS authority:
`Infiltrator-Projects/InfiltratorOS/docs/FILESYSTEM.md`.

```text
/System/Kernel/
├── Images/
│   ├── InfiltratorOS-<component-version>.img
│   ├── InfiltratorOS-<component-version>.config
│   └── InfiltratorOS-<component-version>.map  (when available)
├── Modules/
│   └── InfiltratorOS-<component-version>/
│       └── kernel/.../*.ko
├── Filesystems/
│   └── <format>.ko                 (owned by Filesystem-*; not this package)
├── Firmware/
│   └── ...                         (only verified firmware from its owner)
├── Headers/
│   └── InfiltratorOS-<component-version>/
│       └── ...                     (optional compiled developer headers)
└── Debug/
    └── InfiltratorOS-<component-version>/
        └── ...                     (optional compiled debug symbols)
```

The `Modules/InfiltratorOS-<component-version>/` hierarchy identifies the
native **staged product**; actual module ABI identity is separately recorded
in the staging manifest and binary metadata. This native module hierarchy is made available to Linux kmod through the
new `/System/Kernel/Runtime/InfiltratorOS-0.1.0/modprobe` adapter, which
creates a short-lived dependency-indexed `/run/infiltratoros-kernel` view.
The kernel build uses `CONFIG_MODPROBE_PATH` for kernel-initiated requests.
This only becomes active after a native root and userspace are available;
it does not establish early-initramfs or physical boot qualification. The `Filesystems/` namespace is reserved for the
individual filesystem-provider builds and is not populated by copying every
upstream Linux filesystem module there. EFI BOOT binaries and firmware-stage
drivers belong to the independent **Boot** component, not this repository.

The native Debian packaging contract places every image, header and
debug file exclusively inside `/System/Kernel/`. Historical
`0.1.0-1` packages still had inherited Linux installation paths.
The previous `0.1.0-2` layout correction was incomplete: those
binaries were still built with the **upstream Linux-derived**
`7.0.14-infiltrator` release and module ABI. The current corrected
first-party builder produces **InfiltratorOS Kernel 0.1.0** with
Kbuild UTS release and module ABI **`0.1.1`**, using
Debian package revision **`0.1.0-3`** for the ABI correction,
and **`0.1.0-4`** for the first native kmod/firmware runtime integration. The source `Makefile`
remains upstream Linux `7.0.14` for internal Linux API compatibility.
Native package generation refuses to label new binaries
`7.0.14-infiltrator`. The historical no-compile repacker can still
handle the older source binaries but does not substitute for an actual
freshly compiled `0.1.1` kernel. Native image/modules install in `Images`
and `Modules`; optional developer files in `Headers` and `Debug`.
All these are defined in the authoritative OS filesystem contract.
Native packages have **no** legacy Debian kernel maintainer hooks that
could change the host's initramfs, bootloader or kernel configuration.
This establishes native file placement and a tested kmod discovery/alias
adapter. The adapter's synthetic regression tests do not prove a physical
boot, live module insertion, early initramfs or Setup installation.

The transitional kernel image and modules currently retain Linux ABI
dependencies. Their native staging paths are **not yet a usable replacement
for `/boot` and `/lib/modules`**: runtime kmod indexing and alias resolution
are now implemented without modifying either inherited host path, but native
root availability, early initramfs drivers, UEFI handoff, signed-module
loading, rollback and recovery still need end-to-end verification. No
staging operation claims a bootable installation.

## Native builder and staging

On Mint or Debian, after the full source compilation succeeds:

```bash
make build-only SKIP_DEPS=1
make stage-native
```

`build-only` creates locally compiled Debian kernel packages under
`/Temporary/InfiltratorOS/Kernel/Packages/` and uses
`/Temporary/InfiltratorOS/Kernel/Build/` for **new** object-tree work.
`stage-native` unpacks the compiled image package and writes an **uninstalled**
staging tree under
`/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-<VERSION>/System/Kernel/`,
with `SHA256SUMS.txt` and `STAGING-STATUS.txt`. None of these paths
installs files into the host's actual `/System` directory.

The original first native compile used inherited in-source Kbuild objects and
historical `~/Kernel/dist/` output. All those files remain preserved and
can be explicitly selected for read-only compatibility staging. Kbuild's
internal `debian/` workspace, source names, and original build version are
implementation details required to compile a Linux-derived baseline; they
are **not** native InfiltratorOS installation destinations. On a legacy
in-source build Kbuild itself may also emit packages beside the source tree;
the wrapper copies validated outputs into `/Temporary/InfiltratorOS`
without deleting the originals.

```bash
make package-run
```

Creates a **small** `/Temporary/InfiltratorOS/Kernel/Packages/InfiltratorOS-Kernel-<VERSION>-amd64.run`
which contains a Git commit ID and source downloader, not kernel source.
The public GitHub release distributes the downloader. Running it on
a supported computer creates its temporary workspace automatically, checks
out the exact pinned source from GitHub, then compiles the real local kernel
and packages without relying on old local object files. It stages and
verifies native packages and installs the resulting files into the host's
`/System/Kernel` unless `--build-only` is selected.

**Native file installation is not boot activation.** The installer
does not replace the host's current boot image, module path, EFI files
or NVRAM entries, and does not claim native OS/root/module-loader
qualification. GitHub does not compile or test the kernel as part
of publishing the downloader. The source update must be verified by
a real local compilation and package install.

## Identity and licensing

Keep the existing Linux, Ubuntu and other contributor attribution/licence
records in place. The locally built product and user-facing file names use
InfiltratorOS. Actual internal renaming is an incremental engineering task
requiring driver, module, binary interface and boot verification, not a
global string substitution.

## Boot from an InfiltratorFS kernel source volume

The first Boot + Kernel + InfiltratorFS integration test is now
`tests/infiltratorfs-native-boot.py`, orchestrated by
`scripts/infiltrator/test-infiltratorfs-boot.sh` and exposed via the
GitHub `.run` option `--trial-infiltratorfs`.
An ESP containing **no kernel and no initramfs** holds only Boot and the
InfiltratorFS-owned `drivers_x64/InfiltratorFS_x64.efi` reader.
Both the real kernel image and initramfs live in the separate
Format 0.19 InfiltratorFS disk image. Successful guest evidence must
prove UEFI access, native `0.1.1` execution and a mounted
read/write operation through the matched `infiltratorfs.ko`.

This is an explicitly isolated QEMU/OVMF test using only image files:
no host ESP/EFI/NVRAM changes, physical formatting or host module
insertion. The existing FAT16 handoff test is a separate compatibility
test and is **not accepted as evidence** for this InfiltratorFS-source
requirement. Code and static checks alone do not establish an actual
three-way boot result.
