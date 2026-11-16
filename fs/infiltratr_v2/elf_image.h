/* SPDX-License-Identifier: GPL-2.0-only
 * Private Kernel ELF64 plan for independent freestanding Common V2 modules.
 * Never admit, execute or relocate code using unvalidated source bytes.
 */
#ifndef _IFS_V2_ELF_IMAGE_H
#define _IFS_V2_ELF_IMAGE_H
#include <linux/elf.h>
#include <linux/types.h>
#define IFS_V2_SO_MAX_BYTES (16U * 1024U * 1024U)
#define IFS_V2_IMAGE_MAX_BYTES (32U * 1024U * 1024U)
#define IFS_V2_LOAD_MAX 16U
struct ifs_v2_load_segment {
    u64 source, address, file_bytes, memory_bytes;
    u32 flags;
};
struct ifs_v2_image_plan {
    const u8 *source;
    size_t source_bytes, memory_bytes;
    u64 entry;
    unsigned int count, relocations;
    Elf64_Shdr rela;
    struct ifs_v2_load_segment loads[IFS_V2_LOAD_MAX];
};
/* The caller must authenticate every carrier byte before invoking this. */
int ifs_v2_inspect_elf(const void *carrier, size_t bytes,
                       const char *format, struct ifs_v2_image_plan *plan);
#endif
