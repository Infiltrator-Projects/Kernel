# SPDX-License-Identifier: GPL-2.0
CFLAGS += -D_FILE_OFFSET_BITS=64
CFLAGS += $(KHDR_INCLUDES)

TEST_GEN_PROGS := memfd_test
TEST_PROGS := run_hugetlbfs_test.sh

include ../lib.mk

$(OUTPUT)/memfd_test: memfd_test.c common.c

EXTRA_CLEAN = $(OUTPUT)/common.o
