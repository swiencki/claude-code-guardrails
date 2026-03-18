REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
SCRIPT := $(REPO_ROOT)/scripts/build-settings.sh
target ?= project
layers ?=
dry ?=
overwrite ?=
fragment ?=
profile ?=

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

ifneq ($(profile),)
  PROFILE_FLAG := --profile $(profile)
else
  PROFILE_FLAG :=
endif

.PHONY: help init build remove list show profiles test lint lint-bash lint-json clean

help: ## Show this help
	@echo "Usage: make <target> [target=user|project|/path] [layers=...] [dry=1] [overwrite=1]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'
	@echo ""
	@echo "target options:"
	@echo "  user              user-level settings (all projects)"
	@echo "  project           this repo's settings (default)"
	@echo "  /path/to/dir      a specific project directory"
	@echo ""
	@echo "layers options (comma-separated):"
	@echo "  hooks             hook guardrails"
	@echo "  permissions       tool allow/deny rules"
	@echo "  sub-agents        scoped agent definitions"
	@echo "  (default: all layers)"
	@echo ""
	@echo "Flags:"
	@echo "  dry=1             preview without writing"
	@echo "  overwrite=1       replace existing guardrails instead of merging"
	@echo ""
	@echo "Examples:"
	@echo "  make list                                    # list all fragments"
	@echo "  make profiles                                # list all profiles"
	@echo "  make show fragment=aws/safety.json           # show a fragment's JSON"
	@echo "  make build dry=1                             # preview without writing"
	@echo "  make build                                   # merge all layers"
	@echo "  make build profile=go-dev                    # build from a profile"
	@echo "  make build profile=infra-dev target=user     # profile to user settings"
	@echo "  make build target=user                       # all layers to user settings"
	@echo "  make build layers=hooks                      # merge hooks only"
	@echo "  make build overwrite=1                       # clean install (replace)"
	@echo "  make remove layers=hooks target=user         # remove hooks"
	@echo "  make init profile=go-dev target=~/my-project # init project with profile"

init: ## Initialize a project with guardrails and CLAUDE.md
	@if [ "$(target)" = "project" ]; then \
		echo "Error: init requires a target (e.g. make init target=~/my-project)" >&2; \
		exit 1; \
	fi
	@$(SCRIPT) --target $(target) $(LAYERS_FLAG) $(PROFILE_FLAG) $(DRY_RUN_FLAG) $(OVERWRITE_FLAG)
	@if [ -z "$(dry)" ]; then \
		cp -n $(REPO_ROOT)/layers/1-claude-md/CLAUDE.md $(target)/CLAUDE.md 2>/dev/null \
			&& echo "Copied CLAUDE.md to $(target)/CLAUDE.md" \
			|| echo "CLAUDE.md already exists in $(target), skipped"; \
	fi

build: ## Build settings.json from selected layers or profile
	@$(SCRIPT) --target $(target) $(LAYERS_FLAG) $(PROFILE_FLAG) $(DRY_RUN_FLAG) $(OVERWRITE_FLAG)

remove: ## Remove selected layers from target settings.json
	@$(SCRIPT) --remove --target $(target) $(LAYERS_FLAG) $(DRY_RUN_FLAG)

list: ## List available fragments per layer
	@$(SCRIPT) --list

profiles: ## List available profiles
	@$(SCRIPT) --list-profiles

show: ## Show a fragment's full JSON
	@if [ -z "$(fragment)" ]; then \
		echo "Usage: make show fragment=<name>" >&2; \
		echo "Example: make show fragment=aws/safety.json" >&2; \
		echo "" >&2; \
		$(SCRIPT) --list; \
		exit 1; \
	fi
	@$(SCRIPT) --show $(fragment)

lint: lint-bash lint-json ## Run all linters

lint-bash: ## Lint bash scripts with shellcheck
	@echo "Linting bash scripts..."
	@shellcheck -x $(REPO_ROOT)/scripts/*.sh $(REPO_ROOT)/tests/*.sh
	@echo "All bash scripts passed shellcheck"

lint-json: ## Lint JSON fragments with jq
	@echo "Linting JSON fragments..."
	@failed=0; \
	for f in $$(find $(REPO_ROOT)/layers $(REPO_ROOT)/profiles -name '*.json' 2>/dev/null) $(REPO_ROOT)/.claude/settings.json; do \
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
