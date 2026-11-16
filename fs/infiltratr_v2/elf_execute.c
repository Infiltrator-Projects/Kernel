// SPDX-License-Identifier: GPL-2.0-only
/*
 * InfiltratorOS Common V2 freestanding-image executor, x86-64 only.
 *
 * The *complete* .so carrier is authenticated before this function runs.
 * elf_image.c has already rejected imports, constructors, unsupported
 * relocations, write+execute segments and malformed mappings.
 *
 * Every mounted volume has a separately allocated relocated image; no
 * per-format Kernel parser, fallback driver or helper process is involved.
 */
#include <linux/elf.h>
#include <linux/errno.h>
#include <linux/execmem.h>
#include <linux/infiltratr_fs_v2_adapter.h>
#include <linux/mm.h>
#include <linux/overflow.h>
#include <linux/set_memory.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <asm/elf.h>
#include "elf_image.h"

#define IFS_V2_PROFILE_FREESTANDING (1ULL << 1)
#define IFS_V2_PROFILE_FIRMWARE (1ULL << 3)
#define IFS_V2_GROUP_CORE_BIT (1ULL << 6)
#define IFS_V2_GROUP_VOLUME_BIT (1ULL << 2)
#define IFS_V2_GROUP_METADATA_BIT (1ULL << 1)

typedef const struct ifs_v2_group *(*ifs_v2_query_group)(
        u32 group, u32 minimum_revision, u32 maximum_revision);
struct ifs_v2_module_api {
    u32 abi_version, structure_bytes;
    const char *format_id;
    u64 runtime_profiles, group_mask;
    ifs_v2_query_group query_group;
};
typedef const struct ifs_v2_module_api *(*ifs_v2_entry_fn)(void);

struct ifs_v2_loaded {
    void *memory;
    size_t allocation_bytes;
    struct ifs_v2_image_plan plan;
};

static bool inside(const struct ifs_v2_loaded *image,
                   const void *address, size_t length,
                   unsigned int required, unsigned int forbidden)
{
    unsigned int j;
    uintptr_t start = (uintptr_t)image->memory;
    uintptr_t p = (uintptr_t)address;
    u64 off;

    if (!address || !image->memory || p < start ||
        p - start > image->allocation_bytes ||
        length > image->allocation_bytes - (p - start))
        return false;
    off = p - start;
    for (j = 0; j < image->plan.count; ++j) {
        const struct ifs_v2_load_segment *load = &image->plan.loads[j];
        bool in_relro = image->plan.relro_bytes &&
            off >= image->plan.relro_start &&
            off - image->plan.relro_start <= image->plan.relro_bytes &&
            length <= image->plan.relro_bytes -
                      (off - image->plan.relro_start);
        bool writable = (load->flags & PF_W) && !in_relro;

        if (off >= load->address &&
            off - load->address <= load->memory_bytes &&
            length <= load->memory_bytes - (off - load->address) &&
            (load->flags & required) == required &&
            !(load->flags & (forbidden & ~PF_W)) &&
            (!(forbidden & PF_W) || !writable))
            return true;
    }
    return false;
}

static bool executable(const struct ifs_v2_loaded *image,
                       const void *function)
{
    return inside(image, function, 1, PF_R | PF_X, PF_W);
}

static bool verified_format_id(struct ifs_v2_loaded *image,
                               const char *ptr, const char *expected,
                               char *destination)
{
    unsigned int i;
    if (!ptr || !expected)
        return false;
    for (i = 0; i < 63; ++i) {
        char c;
        if (!inside(image, ptr + i, 1, PF_R, PF_W | PF_X))
            return false;
        c = ptr[i];
        destination[i] = c;
        if (!c)
            return i && !strcmp(destination, expected);
        if (!(c >= 'a' && c <= 'z') &&
            !(c >= '0' && c <= '9') && c != '-' && c != '_')
            return false;
    }
    return false;
}

static bool core_callbacks_valid(struct ifs_v2_loaded *image,
                                 const struct ifs_v2_core *core)
{
    if (!inside(image, core, sizeof(*core), PF_R, PF_W | PF_X) ||
        core->header.abi_version != IFS_V2_ABI ||
        core->header.structure_bytes < sizeof(*core) ||
        core->header.group_id != IFS_V2_GROUP_CORE ||
        core->header.reserved ||
        core->header.capabilities != IFS_V2_CORE_REQUIRED)
        return false;
    if (!executable(image, (const void *)core->probe) ||
        !executable(image, (const void *)core->mount) ||
        !executable(image, (const void *)core->unmount) ||
        !executable(image, (const void *)core->stat) ||
        !executable(image, (const void *)core->directory_entry) ||
        !executable(image, (const void *)core->read))
        return false;
    return !core->write && !core->create && !core->remove &&
           !core->rename && !core->truncate;
}

static bool volume_callbacks_valid(struct ifs_v2_loaded *image,
                                   const struct ifs_v2_volume *volume)
{
    if (!inside(image, volume, sizeof(*volume), PF_R, PF_W | PF_X) ||
        volume->header.abi_version != IFS_V2_ABI ||
        volume->header.structure_bytes < sizeof(*volume) ||
        volume->header.group_id != IFS_V2_GROUP_VOLUME ||
        volume->header.reserved || !volume->header.capabilities)
        return false;
    if ((volume->header.capabilities & 1) != !!volume->query ||
        !!(volume->header.capabilities & 2) != !!volume->label)
        return false;
    return (!volume->query ||
             executable(image, (const void *)volume->query)) &&
           (!volume->label ||
             executable(image, (const void *)volume->label));
}

static bool metadata_callbacks_valid(struct ifs_v2_loaded *image,
                                     const struct ifs_v2_metadata_ops *metadata)
{
    if (!inside(image, metadata, sizeof(*metadata), PF_R, PF_W | PF_X) ||
        metadata->header.abi_version != IFS_V2_ABI ||
        metadata->header.structure_bytes < sizeof(*metadata) ||
        metadata->header.group_id != IFS_V2_GROUP_METADATA ||
        metadata->header.reserved ||
        metadata->header.capabilities != IFS_V2_META_GET_MODE ||
        !executable(image, (const void *)metadata->get) ||
        metadata->set)
        return false;
    return true;
}

static int ifs_v2_bind(struct ifs_v2_loaded *image, const char *format,
                       struct ifs_v2_verified *out)
{
    const struct ifs_v2_module_api *api;
    const struct ifs_v2_core *core;
    const struct ifs_v2_volume *volume = NULL;
    const struct ifs_v2_metadata_ops *metadata = NULL;
    ifs_v2_entry_fn entry;
    void *function;

    function = (u8 *)image->memory + image->plan.entry;
    if (!executable(image, function))
        return -ENOEXEC;
    entry = (ifs_v2_entry_fn)function;
    api = entry();
    if (!inside(image, api, sizeof(*api), PF_R, PF_W | PF_X) ||
        api->abi_version != IFS_V2_ABI ||
        api->structure_bytes < sizeof(*api) ||
        !(api->runtime_profiles &
          (IFS_V2_PROFILE_FREESTANDING | IFS_V2_PROFILE_FIRMWARE)) ||
        !(api->group_mask & IFS_V2_GROUP_CORE_BIT) ||
        (api->group_mask & ~(IFS_V2_GROUP_CORE_BIT |
                             IFS_V2_GROUP_VOLUME_BIT |
                             IFS_V2_GROUP_METADATA_BIT)) ||
        !verified_format_id(image, api->format_id, format,
                            out->format_id) ||
        !executable(image, (const void *)api->query_group))
        return -ENOEXEC;

    core = (const void *)api->query_group(IFS_V2_GROUP_CORE,
                                         IFS_V2_ABI, IFS_V2_ABI);
    if (!core_callbacks_valid(image, core))
        return -ENOEXEC;
    if (api->group_mask & IFS_V2_GROUP_VOLUME_BIT) {
        volume = (const void *)api->query_group(IFS_V2_GROUP_VOLUME,
                                               IFS_V2_ABI, IFS_V2_ABI);
        if (!volume_callbacks_valid(image, volume))
            return -ENOEXEC;
    }
    if (api->group_mask & IFS_V2_GROUP_METADATA_BIT) {
        metadata = (const void *)api->query_group(IFS_V2_GROUP_METADATA,
                                                 IFS_V2_ABI, IFS_V2_ABI);
        if (!metadata_callbacks_valid(image, metadata))
            return -ENOEXEC;
    }
    out->core = core;
    out->volume = volume;
    out->metadata = metadata;
    return 0;
}

static void ifs_v2_release_image(void *lease)
{
    struct ifs_v2_loaded *image = lease;

    if (!image)
        return;
    if (image->memory)
        execmem_free(image->memory);
    kfree(image);
}

/*
 * Execute only after detached signature verification and successful
 * complete ELF validation. The plan stores source views into the signed
 * carrier; it must stay alive throughout copying and relocation.
 */
int ifs_v2_execute_elf(const struct ifs_v2_image_plan *plan,
                       const char *format, struct ifs_v2_verified *out)
{
    struct ifs_v2_loaded *image;
    unsigned int i, pages;
    int ret;

    if (!plan || !format || !out || !plan->count ||
        !plan->memory_bytes ||
        plan->memory_bytes > IFS_V2_IMAGE_MAX_BYTES ||
        !IS_ALIGNED(plan->memory_bytes, PAGE_SIZE))
        return -EINVAL;

    image = kzalloc(sizeof(*image), GFP_KERNEL);
    if (!image)
        return -ENOMEM;
    image->plan = *plan;
    image->allocation_bytes = plan->memory_bytes;
    pages = plan->memory_bytes >> PAGE_SHIFT;
    image->memory = execmem_alloc_rw(EXECMEM_MODULE_TEXT,
                                    plan->memory_bytes);
    if (!image->memory) {
        ret = -ENOMEM;
        goto bad;
    }
    if (!IS_ALIGNED((uintptr_t)image->memory, PAGE_SIZE)) {
        ret = -EFAULT;
        goto bad;
    }

    /* The entire image, including every gap between segments, starts NX.
     * Code becomes executable only when explicitly switched to ROX below. */
    ret = set_memory_nx((unsigned long)image->memory, pages);
    if (ret)
        goto bad;
    memset(image->memory, 0, image->allocation_bytes);
    for (i = 0; i < plan->count; ++i) {
        const struct ifs_v2_load_segment *load = &plan->loads[i];
        memcpy((u8 *)image->memory + load->address,
               plan->source + load->source, load->file_bytes);
    }
    for (i = 0; i < plan->relocations; ++i) {
        Elf64_Rela rela;
        u64 translated;
        memcpy(&rela, plan->source + plan->rela.sh_offset +
               i * sizeof(rela), sizeof(rela));
        translated = (uintptr_t)image->memory + rela.r_addend;
        memcpy((u8 *)image->memory + rela.r_offset,
               &translated, sizeof(translated));
    }

    /* Different segment permissions never share a 4-KiB page; the
     * validator rejects overlapping mapped pages before relocation. */
    for (i = 0; i < plan->count; ++i) {
        const struct ifs_v2_load_segment *load = &plan->loads[i];
        u64 start = round_down(load->address, (u64)PAGE_SIZE);
        u64 limit = round_up(load->address + load->memory_bytes,
                             (u64)PAGE_SIZE);
        unsigned long page = (unsigned long)image->memory + start;
        unsigned int count = (limit - start) >> PAGE_SHIFT;
        if (load->flags & PF_X)
            ret = set_memory_rox(page, count);
        else if (!(load->flags & PF_W))
            ret = set_memory_ro(page, count);
        else
            ret = 0; /* RW + NX from the whole-image protection. */
        if (ret)
            goto bad;
    }
    /* Seal relocatable const tables and the dynamic linker metadata.
     * Never admit a callback descriptor from a writable page. */
    if (plan->relro_bytes) {
        u64 first = round_down(plan->relro_start, (u64)PAGE_SIZE);
        u64 last = round_up(plan->relro_start + plan->relro_bytes,
                            (u64)PAGE_SIZE);

        ret = set_memory_ro((unsigned long)image->memory + first,
                            (last - first) >> PAGE_SHIFT);
        if (ret)
            goto bad;
    }
    ret = ifs_v2_bind(image, format, out);
    if (ret)
        goto bad;
    out->image_lease = image;
    out->release_image = ifs_v2_release_image;
    return 0;

bad:
    ifs_v2_release_image(image);
    memset(out, 0, sizeof(*out));
    return ret;
}
