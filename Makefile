REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
SCRIPT := $(REPO_ROOT)/scripts/build-settings.sh
TARGET ?= project
LAYERS ?=
DRY_RUN ?=

# Build flags from variables
ifneq ($(LAYERS),)
  LAYERS_FLAG := --layers $(LAYERS)
else
  LAYERS_FLAG :=
endif

ifneq ($(DRY_RUN),)
  DRY_RUN_FLAG := --dry-run
else
  DRY_RUN_FLAG :=
endif

.PHONY: help build remove list dry-run test lint lint-bash lint-json clean

help: ## Show this help
	@echo "Usage: make <target> [TARGET=user|project|/path] [LAYERS=hooks,permissions] [DRY_RUN=1]"
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
	@echo "LAYERS options (comma-separated):"
	@echo "  hooks             PreToolUse/PostToolUse hook guardrails"
	@echo "  permissions       tool allow/deny rules"
	@echo "  (default: all layers)"
	@echo ""
	@echo "Examples:"
	@echo "  make build                                  # all layers to repo"
	@echo "  make build TARGET=user                      # all layers to user settings"
	@echo "  make build LAYERS=hooks                     # hooks only"
	@echo "  make build LAYERS=hooks,permissions          # hooks + permissions"
	@echo "  make build DRY_RUN=1                        # preview build without writing"
	@echo "  make remove LAYERS=hooks TARGET=user         # remove hooks from user settings"
	@echo "  make remove DRY_RUN=1 LAYERS=hooks           # preview removal"

build: ## Build settings.json from selected layers
	@$(SCRIPT) --target $(TARGET) $(LAYERS_FLAG) $(DRY_RUN_FLAG)

remove: ## Remove selected layers from target settings.json
	@$(SCRIPT) --remove --target $(TARGET) $(LAYERS_FLAG) $(DRY_RUN_FLAG)

list: ## List available fragments per layer
	@$(SCRIPT) --list

lint: lint-bash lint-json ## Run all linters

lint-bash: ## Lint bash scripts with shellcheck
	@echo "Linting bash scripts..."
	@shellcheck -x $(REPO_ROOT)/scripts/*.sh $(REPO_ROOT)/tests/*.sh
	@echo "All bash scripts passed shellcheck"

lint-json: ## Lint JSON fragments with jq
	@echo "Linting JSON fragments..."
	@failed=0; \
	for f in $$(find $(REPO_ROOT)/layers -name '*.json') $(REPO_ROOT)/.claude/settings.json; do \
		if [ -f "$$f" ] && ! jq empty "$$f" 2>/dev/null; then \
			echo "  FAIL: $$f"; \
			failed=1; \
		fi; \
	done; \
	if [ "$$failed" -eq 1 ]; then exit 1; fi
	@echo "All JSON files are valid"

test: ## Run the test suite
	@$(REPO_ROOT)/tests/run-tests.sh

clean: ## Remove generated .claude/settings.json
	@rm -f $(REPO_ROOT)/.claude/settings.json
	@echo "Removed $(REPO_ROOT)/.claude/settings.json"
