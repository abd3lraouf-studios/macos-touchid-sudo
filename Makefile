# touchid-sudo
PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
SCRIPT := bin/touchid-sudo

.PHONY: help install uninstall enable disable status test lint

help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "};{printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'

install: ## Install touchid-sudo to $(BINDIR) (may prompt for sudo)
	@if [ -w "$(BINDIR)" ]; then \
		install -d "$(BINDIR)" && install -m 755 $(SCRIPT) "$(BINDIR)/touchid-sudo"; \
	else \
		sudo install -d "$(BINDIR)" && sudo install -m 755 $(SCRIPT) "$(BINDIR)/touchid-sudo"; \
	fi
	@echo "Installed to $(BINDIR)/touchid-sudo — run 'sudo touchid-sudo' to enable Touch ID."

uninstall: ## Disable Touch ID for sudo and remove the command
	@if [ -x "$(BINDIR)/touchid-sudo" ]; then sudo "$(BINDIR)/touchid-sudo" --disable || true; fi
	@sudo rm -f "$(BINDIR)/touchid-sudo"
	@echo "Removed $(BINDIR)/touchid-sudo"

enable: ## Enable Touch ID for sudo using the script in this checkout
	@sudo $(SCRIPT)

disable: ## Disable Touch ID for sudo
	@sudo $(SCRIPT) --disable

status: ## Show current Touch ID for sudo state
	@$(SCRIPT) --status

test: ## Run the test suite (no root, no changes to /etc)
	@./tests/run-tests.sh

lint: ## Run shellcheck over every shell script
	@shellcheck -S warning $(SCRIPT) install.sh tests/run-tests.sh && echo "shellcheck clean"
