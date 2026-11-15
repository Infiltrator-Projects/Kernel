# Native Kernel filesystem build compatibility policy

## Corrected build behaviour — 15 November 2026

**Keep Linux's existing native filesystem drivers until the Common V2 .so
kernel/VFS bridge actually mounts and accesses independent test media.**

An installed /System/Filesystems/*.so proves neither that Linux can load the
image into kernel context nor that it can provide a POSIX-mounted namespace.
BOOT and hosted applications have separate execution profiles. In particular,
FILES' v2 formatter support cannot replace the VFS mount implementation.

The native builder starts with the running distribution kernel's /boot/config
and retains its filesystem-driver selections instead of forcibly turning
off the independent-format groups. This applies to built-in (=y) and modular
(=m) configuration. The compatibility gate in
scripts/infiltrator/prune-external-filesystems.c retains the historical
apply/check command-line interface for CI and packaging, but **neither mode
changes the configuration**. The Python counterpart has the same behaviour.

Do **not** disable BTRFS_FS, NTFS3_FS, NTFS_FS, HFS_FS, HFSPLUS_FS,
EXFAT_FS, XFS_FS, AFFS_FS, MINIX_FS or UFS_FS merely because their
independent .so repositories exist. FAT/EXT/VFS, host device drivers and
boot-critical options remain preserved as before. The native builder still
requires built-in EXT4/NVMe/VMD support for the current root path and
continues to enforce the project prohibition on FUSE.

This is a temporary compatibility measure, **not** qualification of the
Common V2 kernel bridge and not a claim that a Linux driver exists for every
Infiltrator filesystem. APFS, for example, has no corresponding standard
in-tree Linux APFS VFS driver in this kernel configuration. A format with no
qualified Linux driver requires a functioning kernel .so bridge before it
can be mounted through ordinary Linux VFS calls.

The independent filesystem repositories remain authoritative for the
on-disk engines. Transitional native drivers cannot be removed until the
exact installed .so, the generic kernel adapter, read/write operations,
mount/umount, concurrent use, durability and root-bootstrap (where
applicable) have passed real on-media tests.

## Validation

The compatibility gates must leave a host .config byte-for-byte unchanged:
- bash tests/native-filesystem-profile.sh
- python3 tests/nonboot-filesystem-build-profile.py

For a native build, confirm the effective .config retains the original
BTRFS, NTFS3, HFS/HFSPLUS and other settings after olddefconfig. Missing
native kernel module packages, incompatible vermagic and an absent driver
are still separate failures; retaining Kconfig entries alone does not
prove an installed machine can mount a particular volume.

No build-policy change edits the host's existing kernel, installed module
tree, mounted partitions, ESP or NVRAM. It takes effect in the next rebuilt
InfiltratorOS kernel and tested module package.
