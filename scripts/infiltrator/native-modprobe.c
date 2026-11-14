// SPDX-License-Identifier: GPL-3.0-or-later
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <libkmod.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

static const char module_parent[] = "/System/Kernel/Modules";
static const char module_directory[] = "/System/Kernel/Modules/InfiltratorOS-" INFILTRATOROS_RELEASE;

static bool trusted_directory(const char *path)
{
	struct stat st;

	return lstat(path, &st) == 0 && S_ISDIR(st.st_mode) && st.st_uid == 0 &&
		!(st.st_mode & (S_IWGRP | S_IWOTH));
}

int main(int argc, char **argv)
{
	struct utsname kernel;
	struct kmod_ctx *context;
	struct kmod_list *modules = NULL, *item;
	bool quiet = false;
	unsigned int flags = 0;
	int position = 1, result = 0;

	/* Both request_module() and the udev rule use this entry point. A
	 * versioned helper must never load modules into the distribution kernel.
	 */
	if (uname(&kernel) != 0 || strcmp(kernel.release, INFILTRATOROS_RELEASE) != 0)
		return 1;
	while (position < argc && argv[position][0] == '-') {
		const char *argument = argv[position++];

		if (strcmp(argument, "--") == 0)
			break;
		if (strcmp(argument, "-q") == 0)
			quiet = true;
		else if (strcmp(argument, "-b") == 0)
			flags |= KMOD_PROBE_APPLY_BLACKLIST;
		else
			return 2;
	}
	if (position != argc - 1 || !argv[position][0] || geteuid() != 0)
		return 2;
	if (!trusted_directory("/System") || !trusted_directory("/System/Kernel") ||
	    !trusted_directory(module_parent) || !trusted_directory(module_directory))
		return 1;
	context = kmod_new(module_directory, NULL);
	if (!context)
		return 1;
	result = kmod_module_new_from_lookup(context, argv[position], &modules);
	if (result >= 0) {
		if (!modules && !quiet)
			result = -ENOENT;
		kmod_list_foreach(item, modules) {
			struct kmod_module *module = kmod_module_get_module(item);
			int loaded = kmod_module_probe_insert_module(module, flags, NULL, NULL, NULL, NULL);

			kmod_module_unref(module);
			if (loaded < 0 && loaded != -EEXIST)
				result = loaded;
		}
	}
	kmod_module_unref_list(modules);
	kmod_unref(context);
	if (result < 0 && !quiet)
		fprintf(stderr, "InfiltratorOS module %s: %s\n", argv[position], strerror(-result));
	return result < 0 ? 1 : 0;
}
