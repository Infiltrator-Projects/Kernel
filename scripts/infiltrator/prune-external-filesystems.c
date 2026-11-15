// SPDX-License-Identifier: GPL-3.0-or-later
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* Compatibility gate for the native Kernel's filesystem build profile.
 *
 * Do not disable the Linux VFS drivers that remain the only qualified way
 * to mount these formats. The Common V2 .so kernel/VFS bridge does not yet
 * execute them. A provider's installed .so or separate .ko source is not
 * evidence that the kernel can mount it.
 *
 * Keep the historical apply/check CLI for the existing builder and CI.
 * Both modes are read-only. A valid host .config is preserved byte for byte.
 */
static const char *const formats[] = {
    "AFFS_FS", "BTRFS_FS", "EXFAT_FS", "HFSPLUS_FS", "HFS_FS",
    "MINIX_FS", "NTFS3_FS", "NTFS_FS", "UFS_FS", "XFS_FS"
};

static int validate_line(const char *line)
{
    size_t i;
    for (i = 0; i < sizeof(formats) / sizeof(formats[0]); ++i) {
        size_t n = strlen(formats[i]);
        if (strncmp(line, "CONFIG_", 7) == 0 &&
            strncmp(line + 7, formats[i], n) == 0 &&
            line[7 + n] == '=') {
            const char *state = line + 8 + n;
            return (state[0] == 'y' || state[0] == 'm' ||
                    state[0] == 'n') &&
                   (state[1] == '\0' || state[1] == '\n' ||
                    (state[1] == '\r' && state[2] == '\n'));
        }
    }
    return 1;
}

int main(int argc, char **argv)
{
    FILE *input;
    struct stat attributes;
    char *line = NULL;
    size_t capacity = 0;
    ssize_t n;
    int result = 0;

    if (argc != 3 || (strcmp(argv[1], "apply") &&
                      strcmp(argv[1], "check"))) {
        fprintf(stderr, "Usage: %s {apply|check} CONFIG\n", argv[0]);
        return 2;
    }
    input = fopen(argv[2], "r");
    if (!input || fstat(fileno(input), &attributes) ||
        !S_ISREG(attributes.st_mode)) {
        fprintf(stderr, "Cannot read a regular kernel configuration\n");
        if (input) fclose(input);
        return 1;
    }
    while ((n = getline(&line, &capacity, input)) >= 0) {
        if (!validate_line(line)) {
            fprintf(stderr, "Invalid filesystem configuration: %s", line);
            result = 1;
            break;
        }
    }
    if (ferror(input)) result = 1;
    free(line);
    fclose(input);
    if (!result) puts("KERNEL_EXTERNAL_FS_PRESERVED");
    return result;
}
