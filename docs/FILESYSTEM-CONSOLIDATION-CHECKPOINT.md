# Filesystem consolidation — resume checkpoint (8 November 2026)

## User-approved objective

Consolidate filesystem implementations across `Infiltrator-Projects/Kernel` and the independently maintained `Infiltrator-Projects/Filesystem-*` repositories. For every supported format, its independent repository owns the best proven on-disk algorithms, validation, recovery and testing. Userspace `.so` and transitional kernel `.ko` must share authoritative format logic where technically possible and have separately tested environment-specific adapters. BOOT, Kernel, Filesystems manager, Defragmenter and InfiltratorOS must retain compatibility.

**Final explicit requirement:** once an independent replacement is qualified, exclude its superseded Linux-derived filesystem module(s) from **Kernel compilation**. Do not confuse this with deleting the entire `fs/` infrastructure or essential kernel support libraries. Do not disable an upstream driver before all overlapping independent formats and their boot/runtime paths are qualified. The end-state must not contain two competing per-format filesystem implementations.

## Confirmed progress — commits on main

- `Filesystem-EXT2` current reviewed main: `c0ad7280fb726bd39ba2b66ad9d04e89ccdc6abc`.
  - `99d0136455a3192a1dde1c2967694838ab21aafa`: `native/filesystems/ext2/core/ext2_core.c` now rejects overlapping block/inode bitmaps and inode tables in EXT2 group descriptors. Same canonical core is compiled for the `.so` and Linux adapter.
  - `0508889a6864c1e79a3e1d064c358741c7320b0d`: independent `tests/test_ext2_metadata_layout.c` with legal, overlapping, and out-of-bounds cases.
  - `c0ad7280fb726bd39ba2b66ad9d04e89ccdc6abc`: CMake/CTest integration.
  - Passed independent engine CI: https://github.com/Infiltrator-Projects/Filesystem-EXT2/actions/runs/42438880143
  - Passed shared library/regression CI: https://github.com/Infiltrator-Projects/Filesystem-EXT2/actions/runs/42438880097
  - This is **not** proof of live `ext2.ko` read/write, remount, fault recovery, or native root boot.
- `Kernel` last checked main: `44112c7572087a8c147f1eb2c482bb59908e36d9` (a newer commit may appear).
  - `scripts/infiltrator/audit-filesystem-modules.py` inventories overlap between kernel `CONFIG_*` settings and independently qualified providers, but intentionally does **not** alter the config.
  - `tests/filesystem-module-ownership.py` verifies shared ownership groups and duplicate alerts. `tests/check.sh` invokes it; `.github/workflows/filesystem-ownership.yml` runs it in CI.
  - Latest observed ownership workflow passed on Kernel main: https://github.com/Infiltrator-Projects/Kernel/actions/runs/42439399126
  - The newer main changed CI action pinning and qualification contracts; re-read main before editing.
  - The previously verified Boot→InfiltratorFS→Kernel two-boot trial is https://github.com/Infiltrator-Projects/Kernel/actions/runs/42434204081 ; the **newer** three-way workflow was still in progress at the checkpoint: https://github.com/Infiltrator-Projects/Kernel/actions/runs/42439399150 .
- No Linux filesystem compilation symbols have been disabled or removed. No independent filesystem has been signed off as a full replacement for its Kernel build-time counterpart.

## Source comparisons / important distinctions

- `Filesystem-EXT2/native/filesystems/ext2/{core,linux}` contains canonical format code and its own Linux VFS adapter; it needs actual ABI-matched `.ko` functional verification.
- `Filesystem-exFAT/native/filesystems/exfat/linux/` is substantially similar but not identical to Kernel `fs/exfat/`. In particular, upstream `fatent.c` has FAT buffer-head caching, discard handling, and changed bitmap/lookup signatures. Assess the whole call graph and independently test before adopting changes; do **not** wholesale replace source.
- `Filesystem-XFS/MIGRATION_STATUS.md` notes the independently owned Defragmenter `XFS.so` while some Linux VFS source history remains elsewhere. Source import alone does not qualify mounting/writing.
- `Filesystem-Btrfs/MIGRATION_STATUS.md` similarly requires standalone and Defragmenter regression before deletion of duplicate source.
- `Filesystem-ZFS` and `Filesystem-APFS` have independent implementations, but they are not direct stock `fs/zfs`/`fs/apfs` copies in this Kernel Git. `Filesystem-Swap` is not a conventional mountable FS counterpart. Do not invent a stock `.ko` to prune.

## Shared upstream driver groups — all owners must qualify before suppression

| Linux-derived Kconfig driver(s) | Independent owner(s) |
| --- | --- |
| `FAT_FS`, `MSDOS_FS`, `VFAT_FS` | FAT12, FAT16, FAT32 |
| `EXFAT_FS` | exFAT |
| `NTFS3_FS` / legacy `NTFS_FS` alias | NTFS |
| `EXT2_FS` | EXT2 |
| `EXT4_FS` (also handles some EXT2/EXT3 media) | EXT2, EXT3, EXT4 |
| `XFS_FS` | XFS |
| `BTRFS_FS` | Btrfs |
| `AFFS_FS` | OFS, FFS |
| `HFS_FS` | HFS |
| `HFSPLUS_FS` (including HFSX) | HFSPlus |
| `MINIX_FS` | Minix |
| `UFS_FS` | UFS1, UFS2 |

The existing audit covers these groups; review additional kernel filesystem formats and shared dependencies before declaring retirement complete. `=y` is a duplicate built-in implementation just as `=m` is a duplicate `.ko`: the final native build policy must address both.

## Resume here — immediate next action

1. **Finish EXT2 qualification first.** Review the exact updated `Filesystem-EXT2` main, compile its independent `ext2.ko` against `0.1.0-infiltrator` (matching `Module.symvers` / vermagic), and perform disposable image probe/mount/read/write/rename/remount/integrity/fault tests. Confirm shared-core behavior with `EXT2.so`, plus consumer integration. The existing CTest successes alone are insufficient.
2. Then compare native exFAT kernel adapter with `Kernel/fs/exfat` function by function; port proven improvements into **Filesystem-exFAT**, preserve its own userspace core, and qualify both ABI targets. Continue other owners format by format, including multi-owner shared groups.
3. For each independently **qualified** replacement, update the Kernel build configuration policy deterministically so superseded format implementations are `not set` for both built-in and module builds; verify `olddefconfig` cannot quietly re-enable them, preserve required support infrastructure, and ensure the kernel still boots and loads the independent `.ko` where required.
4. Run end-to-end Boot→InfiltratorFS→Kernel VM two-boot and relevant other format-image tests on the resulting actual kernel, then packaging/installed-module resolution verification. Never assume `.so` can be directly loaded as a `.ko`.

**Project rules:** main branch only; do not create PR/feature branches; no unverified release or install claims; preserve attribution/licensing and reference source; no destructive physical-disk tests. Do not remove existing working filesystem drivers while a replacement is incomplete.

## Resumption instruction

On returning, read this checkpoint **and the latest GitHub main/CI outcomes**. Start from item 1 above. The end goal remains removal of redundant filesystem **compilation outputs** from Kernel only after the independent providers actually replace them.
