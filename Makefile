REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
SCRIPT    := $(REPO_ROOT)/scripts/build-settings.sh

# Defaults
target  ?= project
layers  ?=
dry     ?=
overwrite ?=
fragment ?=
profile ?=
yes     ?=

# Build flags from variables
FLAGS := --target $(target)
FLAGS += $(if $(layers),--layers $(layers))
FLAGS += $(if $(dry),--dry-run)
FLAGS += $(if $(overwrite),--overwrite)
FLAGS += $(if $(profile),--profile $(profile))
FLAGS += $(if $(yes),--yes)

.PHONY: help build repo remove list show profiles test

help: ## Show available commands
	@echo "Usage: make <command> [target=user|project|/path] [layers=...] [profile=...] [dry=1] [overwrite=1]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make build                          # merge all layers into project settings"
	@echo "  make build dry=1                    # preview without writing"
	@echo "  make build profile=go-dev           # build from a profile"
	@echo "  make build target=user              # apply to user-level settings"
	@echo "  make build layers=hooks             # hooks only"
	@echo "  make build overwrite=1              # replace instead of merge (prompts for confirm)"
	@echo "  make repo target=~/my-project       # set up a repo with guardrails + CLAUDE.md"
	@echo "  make repo profile=go-dev target=~/p # set up a repo with a specific profile"
	@echo "  make show fragment=aws/safety.json  # inspect a fragment"
	@echo "  make remove layers=hooks            # remove hooks from settings"
	@echo "  make build yes=1                    # skip confirmation prompt"

build: ## Build settings.json from layers or profile
	@$(SCRIPT) $(FLAGS)

repo: ## Set up a repo with guardrails + CLAUDE.md
	@$(SCRIPT) --init $(FLAGS)

remove: ## Remove selected layers from settings.json
	@$(SCRIPT) --remove --target $(target) $(if $(layers),--layers $(layers)) $(if $(dry),--dry-run) $(if $(yes),--yes)

list: ## List available fragments
	@$(SCRIPT) --list

profiles: ## List available profiles
	@$(SCRIPT) --list-profiles

show: ## Show a fragment (usage: make show fragment=name)
	@[ -n "$(fragment)" ] || { echo "Usage: make show fragment=<name>" >&2; $(SCRIPT) --list; exit 1; }
	@$(SCRIPT) --show $(fragment)

test: ## Run the test suite
	@$(REPO_ROOT)/tests/run-tests.sh
