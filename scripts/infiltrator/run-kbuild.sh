#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Start a *fresh* top-level Kbuild invocation from our first-party wrapper.
# Invoking "make build-only" exports sub_make_done=1 into its recipe's
# environment. Inheriting that marker makes later Kbuild skip processing O=,
# silently compiling in the source directory instead of the requested objtree.
set -euo pipefail
unset sub_make_done
exec make "$@"
