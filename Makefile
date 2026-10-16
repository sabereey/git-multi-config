SHELL := /bin/bash
PREFIX ?= $(HOME)/.local/bin

.PHONY: help test test-bash32 lint install uninstall

help:
	@printf 'make targets:\n'
	@printf '  test         run the smoke suite in a throwaway HOME\n'
	@printf '  test-bash32  force the system bash (3.2 on macOS)\n'
	@printf '  lint         shellcheck (skips if not installed)\n'
	@printf '  install      install to %s\n' "$(PREFIX)"
	@printf '  uninstall    remove the installed binary\n'

test:
	bash tests/smoke.sh

test-bash32:
	GMC_TEST_BASH=/bin/bash bash tests/smoke.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -s bash -S error git-multi-config.sh install.sh tests/smoke.sh && echo "shellcheck: no errors"; \
	else \
		echo "shellcheck not installed, skipping"; \
	fi

install:
	PREFIX="$(PREFIX)" ./install.sh

uninstall:
	rm -f "$(PREFIX)/git-multi-config"
	@echo "removed $(PREFIX)/git-multi-config"
