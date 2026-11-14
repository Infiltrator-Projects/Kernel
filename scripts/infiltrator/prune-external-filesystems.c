// SPDX-License-Identifier: GPL-3.0-or-later
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Keep this list aligned with the independent filesystem build profile.
 * The bootstrap and shared VFS settings are intentionally absent. */
static const char *const retired[] = {
    "AFFS_FS", "BTRFS_FS", "EXFAT_FS", "HFSPLUS_FS", "HFS_FS",
    "MINIX_FS", "NTFS3_FS", "NTFS_FS", "UFS_FS", "XFS_FS"
};

static int symbol_index(const char *line, const char **value)
{
    size_t i;
    for (i = 0; i < sizeof(retired) / sizeof(retired[0]); ++i) {
        size_t n = strlen(retired[i]);
        if (!strncmp(line, "CONFIG_", 7) && !strncmp(line + 7, retired[i], n) &&
            line[7 + n] == '=') {
            *value = line + 8 + n;
            return (int)i;
        }
        if (!strncmp(line, "# CONFIG_", 9) && !strncmp(line + 9, retired[i], n) &&
            !strcmp(line + 9 + n, " is not set")) {
            *value = "n";
            return (int)i;
        }
    }
    return -1;
}

int main(int argc, char **argv)
{
    const size_t count = sizeof(retired) / sizeof(retired[0]);
    int seen[sizeof(retired) / sizeof(retired[0])] = {0};
    char *line = NULL, *temporary = NULL;
    size_t capacity = 0, i;
    ssize_t length;
    FILE *input = NULL, *output = NULL;
    struct stat attributes;
    int apply, fd = -1, result = 1, final_newline = 1;

    if (argc != 3 || (strcmp(argv[1], "apply") && strcmp(argv[1], "check"))) {
        fprintf(stderr, "Usage: %s {apply|check} CONFIG\n", argv[0]);
        return 2;
    }
    apply = !strcmp(argv[1], "apply");
    input = fopen(argv[2], "r");
    if (!input || fstat(fileno(input), &attributes)) goto done;
    if (!S_ISREG(attributes.st_mode)) { errno = EINVAL; goto done; }
    if (apply) {
        size_t n = strlen(argv[2]) + sizeof(".infiltrator-XXXXXX");
        temporary = malloc(n);
        if (!temporary) goto done;
        snprintf(temporary, n, "%s.infiltrator-XXXXXX", argv[2]);
        fd = mkstemp(temporary);
        if (fd < 0 || fchmod(fd, attributes.st_mode & 0777)) goto done;
        output = fdopen(fd, "w");
        if (!output) goto done;
        fd = -1;
    }
    while ((length = getline(&line, &capacity, input)) >= 0) {
        const char *value = NULL;
        char terminator;
        int index;
        size_t text_length = (size_t)length;
        while (text_length && (line[text_length - 1] == '\n' || line[text_length - 1] == '\r'))
            --text_length;
        terminator = line[text_length];
        line[text_length] = '\0';
        index = symbol_index(line, &value);
        if (index >= 0) {
            if (strcmp(value, "y") && strcmp(value, "m") && strcmp(value, "n")) {
                fprintf(stderr, "Invalid kernel filesystem setting: %s\n", line);
                errno = EINVAL;
                goto done;
            }
            if (!apply && strcmp(value, "n")) {
                fprintf(stderr, "Superseded kernel filesystem is active: %s\n", retired[index]);
                errno = EINVAL;
                goto done;
            }
            if (apply && !seen[index] && fprintf(output, "# CONFIG_%s is not set\n", retired[index]) < 0)
                goto done;
            seen[index] = 1;
            if (apply) final_newline = 1;
        } else if (apply) {
            /* Restore the original line terminators, if any. */
            line[text_length] = terminator;
            if (fwrite(line, 1, (size_t)length, output) != (size_t)length) goto done;
            final_newline = length > 0 && line[length - 1] == '\n';
        }
    }
    if (ferror(input)) goto done;
    if (apply) {
        for (i = 0; i < count; ++i) {
            if (!seen[i]) {
                if (!final_newline && fputc('\n', output) == EOF) goto done;
                final_newline = 1;
                if (fprintf(output, "# CONFIG_%s is not set\n", retired[i]) < 0) goto done;
            }
        }
        if (fclose(output)) { output = NULL; goto done; }
        output = NULL;
        if (rename(temporary, argv[2])) goto done;
    }
    result = 0;
    puts(apply ? "KERNEL_EXTERNAL_FS_PRUNE_APPLIED" : "KERNEL_EXTERNAL_FS_PRUNE_PASS");
done:
    if (result) fprintf(stderr, "Kernel filesystem profile failed: %s\n", strerror(errno));
    free(line);
    if (input) fclose(input);
    if (output) fclose(output);
    if (fd >= 0) close(fd);
    if (temporary) { if (result) unlink(temporary); free(temporary); }
    return result;
}
