# SPDX-License-Identifier: GPL-3.0-or-later
.PHONY: help probe configure-only build-only check
EXTRA = $(if $(JOBS),--jobs $(JOBS),) $(if $(filter 1,$(SKIP_DEPS)),--skip-deps,)
help:
	@bash scripts/build-native.sh --help
probe:
	@bash scripts/build-native.sh --probe
configure-only:
	@bash scripts/build-native.sh --configure-only $(EXTRA)
build-only:
	@bash scripts/build-native.sh --build-only $(EXTRA)
check:
	@bash tests/check.sh
