REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
SCRIPT := $(REPO_ROOT)/scripts/build-settings.sh
TARGET ?= project

.PHONY: help build hooks permissions list dry-run test clean

help: ## Show this help
	@echo "Usage: make <target> [TARGET=user|project|/path]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'
	@echo ""
	@echo "TARGET options:"
	@echo "  user              ~/.claude/settings.json (all projects)"
	@echo "  project           this repo's .claude/settings.json (default)"
	@echo "  /path/to/project  a specific project directory"
	@echo ""
	@echo "Examples:"
	@echo "  make build                       # build to repo .claude/settings.json"
	@echo "  make build TARGET=user           # install to user-level settings"
	@echo "  make build TARGET=~/my-project   # install to specific project"
	@echo "  make hooks TARGET=user           # install hooks only"
	@echo "  make dry-run TARGET=user         # preview without writing"

build: ## Build settings.json from all layers
	@$(SCRIPT) --target $(TARGET)

hooks: ## Build hooks only (no permissions)
	@$(SCRIPT) --target $(TARGET) --hooks-only

permissions: ## Build permissions only (no hooks)
	@$(SCRIPT) --target $(TARGET) --permissions-only

list: ## List available hook and permission fragments
	@$(SCRIPT) --list

dry-run: ## Preview merged output without writing
	@$(SCRIPT) --target $(TARGET) --dry-run

test: ## Run the test suite
	@$(REPO_ROOT)/tests/run-tests.sh

clean: ## Remove generated .claude/settings.json
	@rm -f $(REPO_ROOT)/.claude/settings.json
	@echo "Removed $(REPO_ROOT)/.claude/settings.json"
