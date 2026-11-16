# Infiltratr Common V2 kernel filesystem bridge

This subtree is a Linux VFS consumer of independent filesystem providers,
NOT a filesystem engine, native EXT4 replacement or FUSE driver.

The Common V2 ABI is owned by Libraries. Its fixed-width kernel-facing
layout is represented in `include/linux/infiltratr_fs_v2_adapter.h`; it does
not create a new ABI. The Linux VFS layer supplies read-only inode, lookup,
directory and file operations, and a bounded partition-relative I/O host.

**Current status:** VFS adapter and strict load boundary are implemented
in source. The ELF admission stub deliberately returns `-EOPNOTSUPP`:
no unverified code will execute and no native filesystem fallback exists.
This does **not yet mount any .so**.

Required for completion:
1. Authenticate the actual installed `/System/Filesystems/<FORMAT>.so`
   before interpreting the embedded `.infiltrator_boot` ELF.
2. Validate and relocate the exact no-import Common V2 freestanding image,
   enforce executable memory W^X permissions, and verify callback ranges.
3. Mount from one independently owned provider; securely retain its image
   for the full mount lifetime, including concurrent active mounts.
4. Qualify a clean EXT4 root in QEMU with native EXT4 disabled; reject
   corrupt, missing or unsigned engines; test real data/metadata reads.
5. Only then remove the transitional native EXT4 bootstrap driver.

Do not call this complete based on source compilation, VFS registration,
or Boot's separate EFI filesystem read qualification.

## Mount parameters and executable file support

The VFS adapter has an explicit and validated `format=<id>` parameter.
The ID selects an independently installed V2 module, never a built-in
format parser. The `read_folio` path is backed exclusively by `CORE.READ`,
so normal file reads, memory mappings, and executable page faults do not
bypass the Common V2 provider. All mounts remain read-only.

Until signed ELF admission is actually implemented and qualified, these
operations cannot complete a mount; compilation does not prove runnability.

## Detached-signature admission stage

A verified provider must be read from `/System/Filesystems/FORMAT.so`
using a validated format ID, and accompanied by `FORMAT.so.p7s`, a
detached PKCS#7 signature trusted by the Kernel keyring. The signature
covers the entire exact `.so` image, including its `.infiltrator_boot`
section. The installed carrier is never executed directly.

The non-executing ELF validation rejects foreign architecture, malformed
section/program ranges, dynamic imports, TLS, constructors, W+X segments,
non-relative relocations, and missing or mismatched Common V2 identity.
Until executable-image protection and lifetime qualification are finished,
a correctly signed and valid module still returns `-EOPNOTSUPP`; unsigned
or modified images are rejected earlier. A signature is not a substitute
for a complete VFS/early-boot test.

## Protected executable Common V2 image

The signed ELF admission stage now invokes the isolated x86-64 executable
mapping only for the validated no-import freestanding image. The Kernel
rejects any missing or untrusted detached signature, loader imports,
W+X segment, foreign descriptor, wrong format ID, out-of-image callbacks,
unsupported mutable Common V2 core operations, or relocation outside its
writable signed image. Each mount gets independent image code/data and a
lifetime lease released only at unmount. Code pages are ROX; data and gaps
are NX. The ordinary hosted SO is never executed as Kernel code.

**Qualification caveat:** source-level protection and a successful compile do
not demonstrate actual device mounting or usable system roots. The .p7s
signature must be produced by a key trusted by the running InfiltratorOS
Kernel, and an isolated signed-module QEMU mount test must pass before the
installer enables this path or removes the native bootstrap.

## Common V2 mode and ownership metadata

When a signed provider advertises `METADATA.GET_MODE`, the generic VFS
adapter queries it for every inode and preserves the format owner's
file execution bits and UID/GID without ever decoding an on-disk format.
A mismatch between the provider's reported type and the Core's type is
a corruption error; a missing metadata group keeps conservative read-only
permissions rather than inventing execute permission. This is needed for
executables on real system volumes and remains subject to VM qualification.

## Block-device geometry fix

InfiltratorOS Kernel Common V2 mounts use the opened block device's
`bdev_nr_bytes` and `bdev_logical_block_size`, never the device node's
inode `i_size`, which can be zero even for a valid partition. Regular-file
test images retain ordinary file-size geometry. This fixes an actual guest
boot regression that reached the VFS mount and returned `-ENODEV`.

## Relocatable read-only provider descriptors

The freestanding Common V2 ELF commonly stores its callback tables in the
signed `.data.rel.ro` section. The generic loader now validates the
`PT_GNU_RELRO` page range against its writable load segment, performs
signed relative relocations while NX, and then changes the complete RELRO
pages to read-only before calling a provider function. The descriptor
validator recognises those pages as effectively RO; ordinary writable data
never qualifies as an immutable callback table. This avoids introducing
format-specific code or weakening executable memory policy.
