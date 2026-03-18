REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
SCRIPT := $(REPO_ROOT)/scripts/build-settings.sh
target ?= project
layers ?=
dry ?=
overwrite ?=

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

ifneq ($(overwrite),)
  OVERWRITE_FLAG := --overwrite
else
  OVERWRITE_FLAG :=
endif

.PHONY: help init build remove list test lint lint-bash lint-json clean

help: ## Show this help
	@echo "Usage: make <target> [target=user|project|/path] [layers=...] [dry=1] [overwrite=1]"
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
	@echo "  sub-agents        scoped agent definitions (.claude/agents/)"
	@echo "  (default: all layers)"
	@echo ""
	@echo "Flags:"
	@echo "  dry=1             preview without writing"
	@echo "  overwrite=1       replace existing guardrails instead of merging"
	@echo ""
	@echo "Examples:"
	@echo "  make build                                  # merge all layers"
	@echo "  make build target=user                      # merge all to user settings"
	@echo "  make build layers=hooks                     # merge hooks only"
	@echo "  make build overwrite=1                      # clean install (replace existing)"
	@echo "  make build dry=1                            # preview without writing"
	@echo "  make remove layers=hooks target=user         # remove hooks from user settings"
	@echo "  make init target=~/my-project                # guardrails + CLAUDE.md"

init: ## Initialize a project with guardrails and CLAUDE.md
	@if [ "$(target)" = "project" ]; then \
		echo "Error: init requires a target (e.g. make init target=~/my-project)" >&2; \
		exit 1; \
	fi
	@$(SCRIPT) --target $(target) $(LAYERS_FLAG) $(DRY_RUN_FLAG) $(OVERWRITE_FLAG)
	@if [ -z "$(dry)" ]; then \
		cp -n $(REPO_ROOT)/layers/1-claude-md/CLAUDE.md $(target)/CLAUDE.md 2>/dev/null \
			&& echo "Copied CLAUDE.md to $(target)/CLAUDE.md" \
			|| echo "CLAUDE.md already exists in $(target), skipped"; \
	fi

build: ## Build settings.json from selected layers (merges by default)
	@$(SCRIPT) --target $(target) $(LAYERS_FLAG) $(DRY_RUN_FLAG) $(OVERWRITE_FLAG)

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
