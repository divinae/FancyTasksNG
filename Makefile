# SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
# SPDX-License-Identifier: GPL-2.0-or-later

# FancyTasksNG Makefile
.PHONY: all build install update test preview lint clean diag

all: build

build:
	@./tools/build.sh

install:
	@./tools/install.sh

uninstall:
	@./tools/uninstall.sh

update:
	@./tools/update.sh

test:
	@python3 -m unittest discover -s tests

preview:
	@./tools/testing.sh

lint:
	@ruff check --select E9,F package/contents/ui/code tools .github/scripts tests
	@shellcheck --severity=warning tools/*.sh
	@python3 tools/sync_defaults.py --check
	@python3 -m json.tool package/metadata.json > /dev/null

clean:
	@rm -rf build release
	@echo "Cleanup complete."

diag:
	@./tools/diag.sh
