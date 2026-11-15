#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Populate package provenance for an explicitly selected, pinned source tree.
# Do not assume that the running distribution's headers describe this tree.
native_source_identity() {
  local identity="$1/docs/upstream/source-id"
  pkg=pinned-git-source
  ver=unknown
  if [[ -e "$identity" ]]; then
    [[ -f "$identity" && -r "$identity" ]] || return 1
    IFS='=' read -r pkg ver < "$identity" || return 1
    [[ -n "$pkg" && -n "$ver" && "$ver" != *'='* ]] || return 1
  fi
}
