// SPDX-License-Identifier: GPL-2.0-only
/*
 * InfiltratorOS Common V2 verified provider admission.
 * The ordinary hosted library must never execute inside the Kernel.
 * Only a detached PKCS#7 signature trusted by the Kernel's keyring
 * authorises the exact installed bytes for ELF validation.
 *
 * This stage validates without executing. The executor is a separate
 * step and will remain disabled until W^X, lifetime and descriptor
 * validation are independently qualified. No fallback parser is allowed.
 */
#include <linux/errno.h>
#include <linux/infiltratr_fs_v2_adapter.h>
#include <linux/kernel_read_file.h>
#include <linux/limits.h>
#include <linux/verification.h>
#include <linux/vmalloc.h>
#include <linux/string.h>
#include "elf_image.h"

#define IFS_V2_MAX_SIGNATURE (128U * 1024U)

int ifs_v2_elf_acquire(const char *format, struct ifs_v2_verified *verified)
{
    char path[128], signature_path[144];
    void *library = NULL, *signature = NULL;
    struct ifs_v2_image_plan plan;
    ssize_t library_bytes, signature_bytes;
    size_t i, count;
    int ret;

    if (!verified || !format)
        return -EINVAL;
    memset(verified, 0, sizeof(*verified));
    count = strnlen(format, sizeof(verified->format_id));
    if (!count || count >= sizeof(verified->format_id))
        return -EINVAL;
    for (i = 0; i < count; ++i)
        if (!(format[i] >= 'a' && format[i] <= 'z') &&
            !(format[i] >= '0' && format[i] <= '9') &&
            format[i] != '-' && format[i] != '_')
            return -EINVAL;

    /* Package filenames are uppercase; Common V2 format IDs are lowercase.
     * No caller controls path separators or arbitrary ELF search paths. */
    if (scnprintf(path, sizeof(path), "/System/Filesystems/%s.so", format)
        >= sizeof(path))
        return -ENAMETOOLONG;
    for (i = sizeof("/System/Filesystems/") - 1; path[i] != '.'; ++i)
        if (path[i] >= 'a' && path[i] <= 'z')
            path[i] -= 'a' - 'A';
    if (scnprintf(signature_path, sizeof(signature_path), "%s.p7s", path)
        >= sizeof(signature_path))
        return -ENAMETOOLONG;

    library_bytes = kernel_read_file_from_path(path, 0, &library,
                                               IFS_V2_SO_MAX_BYTES, NULL,
                                               READING_MODULE);
    if (library_bytes < 0)
        return library_bytes;

    signature_bytes = kernel_read_file_from_path(
        signature_path, 0, &signature, IFS_V2_MAX_SIGNATURE, NULL,
        READING_POLICY);
    if (signature_bytes < 0) {
        ret = -EKEYREJECTED;
        goto out;
    }

    /* This is a detached signature over the WHOLE carrier byte-for-byte,
     * not over an unchecked ELF section chosen by the loader. */
    ret = verify_pkcs7_signature(library, library_bytes,
                                 signature, signature_bytes,
                                 VERIFY_USE_SECONDARY_KEYRING,
                                 VERIFYING_MODULE_SIGNATURE, NULL, NULL);
    if (ret) {
        ret = -EKEYREJECTED;
        goto out;
    }
    ret = ifs_v2_inspect_elf(library, library_bytes, format, &plan);
    if (ret)
        goto out;

    /* Stage 2 must allocate protected executable memory and retain it
     * through unmount. Do NOT cast a userspace .so to a .ko or bypass
     * verification because the filesystem has a familiar name. */
    ret = -EOPNOTSUPP;
out:
    vfree(signature);
    vfree(library);
    return ret;
}
