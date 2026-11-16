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
