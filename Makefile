REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
SCRIPT := $(REPO_ROOT)/scripts/build-settings.sh
target ?= project
layers ?=
dry ?=

# Build flags from variables
ifneq ($(layers),)
  LAYERS_FLAG := --layers $(layers)
else
  LAYERS_FLAG :=
endif

ifneq ($(dry),)
  DRY_RUN_FLAG := --dry-run
else
  DRY_RUN_FLAG :=
endif

.PHONY: help build remove list test lint lint-bash lint-json clean

help: ## Show this help
	@echo "Usage: make <target> [target=user|project|/path] [layers=hooks,permissions] [dry=1]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'
	@echo ""
	@echo "target options:"
	@echo "  user              ~/.claude/settings.json (all projects)"
	@echo "  project           this repo's .claude/settings.json (default)"
	@echo "  /path/to/project  a specific project directory"
	@echo ""
	@echo "layers options (comma-separated):"
	@echo "  hooks             PreToolUse/PostToolUse hook guardrails"
	@echo "  permissions       tool allow/deny rules"
	@echo "  (default: all layers)"
	@echo ""
	@echo "Examples:"
	@echo "  make build                                  # all layers to repo"
	@echo "  make build target=user                      # all layers to user settings"
	@echo "  make build layers=hooks                     # hooks only"
	@echo "  make build layers=hooks,permissions          # hooks + permissions"
	@echo "  make build dry=1                            # preview build without writing"
	@echo "  make remove layers=hooks target=user         # remove hooks from user settings"
	@echo "  make remove dry=1 layers=hooks               # preview removal"

build: ## Build settings.json from selected layers
	@$(SCRIPT) --target $(target) $(LAYERS_FLAG) $(DRY_RUN_FLAG)

remove: ## Remove selected layers from target settings.json
	@$(SCRIPT) --remove --target $(target) $(LAYERS_FLAG) $(DRY_RUN_FLAG)

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
