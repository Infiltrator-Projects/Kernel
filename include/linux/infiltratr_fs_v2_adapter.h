/* SPDX-License-Identifier: GPL-2.0-only
 * Kernel's layout view of the *existing* Infiltratr Common V2 ABI.
 *
 * This is not a second filesystem ABI. The canonical API and enumerations
 * are maintained in Libraries/include/infiltratr/filesystem_module_v2.h.
 * These fixed-width Linux types have the identical LP64 x86-64 layout.
 * The executable SO loader must validate the complete canonical descriptor
 * before providing any callback address to this adapter.
 */
#ifndef _LINUX_INFILTRATR_FS_V2_ADAPTER_H
#define _LINUX_INFILTRATR_FS_V2_ADAPTER_H
#include <linux/types.h>
#include <linux/stddef.h>

#define IFS_V2_ABI 2
#define IFS_V2_GROUP_CORE 7
#define IFS_V2_GROUP_VOLUME 3
#define IFS_V2_ENTRY_FILE 1
#define IFS_V2_ENTRY_DIR 2
#define IFS_V2_ENTRY_LINK 3
#define IFS_V2_END 1
#define IFS_V2_NOT_FOUND 2
#define IFS_V2_INVALID -1
#define IFS_V2_IO_ERROR -2
#define IFS_V2_CORRUPT -3
#define IFS_V2_UNSUPPORTED -8
#define IFS_V2_READ_ONLY (1ULL << 0)
#define IFS_V2_CORE_REQUIRED ((1ULL << 0) | (1ULL << 1) | \
                              (1ULL << 2) | (1ULL << 3) | (1ULL << 4))
#define IFS_V2_PATH_MAX 4096
#define IFS_V2_MAX_NAME 255
#define IFS_V2_MAX_READ 4096

struct ifs_v2_host {
    u32 abi_version, structure_bytes;
    u64 capabilities, volume_bytes;
    u32 logical_sector_bytes, physical_sector_bytes, maximum_transfer_bytes;
    u32 reserved;
    void *context;
    int (*read_at)(void *, u64, void *, u32);
    int (*write_at)(void *, u64, const void *, u32);
    int (*flush)(void *);
    int (*discard)(void *, u64, u64);
    void *(*allocate)(void *, size_t);
    void (*release)(void *, void *);
    void *(*create_lock)(void *);
    void (*destroy_lock)(void *, void *);
    void (*lock)(void *, void *);
    void (*unlock)(void *, void *);
    u64 (*monotonic_ns)(void *);
    u64 (*realtime_ns)(void *);
    int (*cancelled)(void *);
    void (*log)(void *, u32, const char *);
    int (*random_bytes)(void *, void *, u32);
};

struct ifs_v2_group {
    u32 abi_version, structure_bytes, group_id, reserved;
    u64 capabilities;
};
struct ifs_v2_entry {
    u32 structure_bytes, type;
    u64 size_bytes;
    u32 attributes, name_bytes;
    char *name;
    u32 name_capacity;
};
struct ifs_v2_volume_info {
    u32 structure_bytes, variant, max_name_bytes, block_bytes;
    u64 total_bytes, free_bytes;
};
struct ifs_v2_core {
    struct ifs_v2_group header;
    int (*probe)(const struct ifs_v2_host *, u32 *);
    int (*mount)(const struct ifs_v2_host *, void **,
                 struct ifs_v2_volume_info *);
    int (*unmount)(void *);
    int (*stat)(void *, const char *, struct ifs_v2_entry *);
    int (*directory_entry)(void *, const char *, u32, struct ifs_v2_entry *);
    int (*read)(void *, const char *, u64, void *, u32);
    int (*write)(void *, const char *, u64, const void *, u32);
    int (*create)(void *, const char *, u32);
    int (*remove)(void *, const char *);
    int (*rename)(void *, const char *, const char *);
    int (*truncate)(void *, const char *, u64);
};
struct ifs_v2_volume {
    struct ifs_v2_group header;
    int (*query)(void *, struct ifs_v2_volume_info *);
    int (*label)(void *, char *, u32, u32 *);
    /* The read-only VFS adapter must NEVER invoke any mutators. */
};

/* Returned by the *authenticated* ELF loader only, never by format guesses.
 * The loader retains ownership of code/data until the last mount drops it.
 */
struct ifs_v2_verified {
    char format_id[64];
    const struct ifs_v2_core *core;
    const struct ifs_v2_volume *volume;
    void *image_lease;
    void (*release_image)(void *);
};
int ifs_v2_elf_acquire(const char *format, struct ifs_v2_verified *verified);
#endif
