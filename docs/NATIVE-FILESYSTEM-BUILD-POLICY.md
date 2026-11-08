# Native Kernel filesystem build profile

The normal InfiltratorOS `make configure-only` and `make build-only`
builder starts from the host Mint/Debian kernel configuration. That host
configuration often requests duplicate in-tree filesystem drivers even
after their independent `Filesystem-*` repositories have been extracted.

To stop recompiling those implementations, the native builder calls
`scripts/infiltrator/prune-external-filesystems.py apply` on its **private
build object `.config`**, then runs `olddefconfig` and
`prune-external-filesystems.py check` before any real build.
The actual three-way Boot → InfiltratorFS → Kernel QEMU workflow applies
and checks the exact same profile.

## Excluded from the native kernel image and module build

| In-tree Kconfig | Independent format owner |
| --- | --- |
| `EXFAT_FS` | Filesystem-exFAT |
| `NTFS3_FS`, `NTFS_FS` | Filesystem-NTFS |
| `XFS_FS` | Filesystem-XFS |
| `BTRFS_FS` | Filesystem-Btrfs |
| `HFS_FS` | Filesystem-HFS |
| `HFSPLUS_FS` | Filesystem-HFSPlus (including HFSX) |
| `AFFS_FS` | Filesystem-OFS and Filesystem-FFS |
| `MINIX_FS` | Filesystem-Minix |
| `UFS_FS` | Filesystem-UFS1 and Filesystem-UFS2 |

Both `=y` and `=m` are suppressed. The format source under
`Kernel/fs/` is **not deleted**: it remains reference/provenance code
and can still be compiled by deliberately running raw Linux Kbuild with
another independent configuration. The native build profile removes it
from the **normal InfiltratorOS Kbuild selection**.

## Kept for the current boot/recovery transition

`FAT_FS`, `VFAT_FS`, `MSDOS_FS`, `EXT2_FS`, `EXT4_FS`
and their shared `JBD2`/`FS_MBCACHE` helpers are not changed by the
profile. Neither are proc, sysfs, devtmpfs, initramfs, squashfs, VFS,
networking, block device/EFI drivers or unrelated filesystems.

The three-way QEMU boot path obtains the kernel and initramfs from
InfiltratorFS. Its FAT32 EFI bootstrap is provided by Boot, not by
in-tree Linux FAT drivers. The recovery fallback remains while independent
FAT and EXT2/4 modules are separately ABI-qualified.

## Important runtime boundary

This deliberately saves **kernel compilation** rather than magically
making Linux userspace `.so` files mountable in the native kernel.
Existing independently released `.ko` binaries were largely built for
Linux 6.12.107. The native InfiltratorOS Kernel has a **different module
ABI and `vermagic`** (currently 0.1.1). Those old `.ko` artifacts cannot
be loaded as replacements until rebuilt against the native
`Module.symvers`, qualified on disposable media, and made discoverable
by the native module loader. The non-boot formats above may therefore
be **temporarily unavailable for native kernel mounts** even though
their userspace `.so` interfaces remain separate.

To inspect the exact build output after `make configure-only`:

```sh
python3 scripts/infiltrator/prune-external-filesystems.py check /Temporary/InfiltratorOS/Kernel/Build/obj/.config
grep -E '^CONFIG_(XFS_FS|BTRFS_FS|NTFS3_FS|EXFAT_FS|FAT_FS|EXT4_FS)=' /Temporary/InfiltratorOS/Kernel/Build/obj/.config
```

Tests: `python3 tests/nonboot-filesystem-build-profile.py`,
`make check`, and the real three-way VM qualification. This profile
does not change Mint's host kernel, EFI/NVRAM or installed modules.
