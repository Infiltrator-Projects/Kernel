// SPDX-License-Identifier: GPL-2.0-only
/*
 * Strict kernel ELF admission gate. Loading a hosted glibc SO into kernel
 * memory is forbidden. Once the no-import, freestanding V2 ELF executor
 * is qualified, it will validate and return its exact module callback table.
 *
 * Deliberately fail closed until cryptographic authentication, relocation,
 * W^X enforcement, module lifetime and read-only root safety are qualified.
 * This MUST NOT call the Linux native filesystem drivers or fall back to
 * an unrelated mount implementation.
 */
#include <linux/errno.h>
#include <linux/infiltratr_fs_v2_adapter.h>
#include <linux/string.h>

int ifs_v2_elf_acquire(const char *format, struct ifs_v2_verified *verified)
{
    if (!verified)
        return -EINVAL;
    memset(verified, 0, sizeof(*verified));
    return -EOPNOTSUPP;
}
