REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
SCRIPT    := $(REPO_ROOT)/scripts/build-settings.sh

# Defaults
target  ?= user
layers  ?=
dry     ?=
replace ?=
overwrite ?=
fragment ?=
fragement ?=
profile ?=
yes     ?=
event   ?= PreToolUse
tool    ?= Bash
matcher ?=
hook    ?=
command ?=
input   ?=
expect  ?=

# Build flags from variables
FLAGS := --target $(target)
FLAGS += $(if $(layers),--layers $(layers))
FLAGS += $(if $(dry),--dry-run)
FLAGS += $(if $(replace),--overwrite)
FLAGS += $(if $(overwrite),--overwrite)
FLAGS += $(if $(profile),--profile $(profile))
FLAGS += $(if $(yes),--yes)

.PHONY: help help-advanced build repo remove list show profiles test probe

help: ## Show available commands
	@echo "Usage: make <command> [profile=name] [target=user|project|/path]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
	@echo ""
	@echo "Recommended:"
	@echo "  make profiles"
	@echo "  make build profile=default"
	@echo "  make build profile=go-dev"
	@echo "  make build profile=go-dev dry=1"
	@echo "  make repo profile=infra-dev target=~/my-project"
	@echo "  make remove profile=default"
	@echo "  make show profile=default fragment=git"
	@echo "  make probe profile=default command='git push --force origin main'"
	@echo ""
	@echo "Run 'make help-advanced' for layers=, replace=1, and other low-level options."

help-advanced: ## Show advanced flags and low-level workflows
	@echo "Advanced usage: make <command> [profile=name] [target=user|project|/path] [dry=1] [replace=1]"
	@echo ""
	@echo "Advanced flags:"
	@echo "  target=...     # user (default), project, or a specific repo path"
	@echo "  dry=1          # preview without writing"
	@echo "  replace=1      # replace generated layers instead of merging them"
	@echo "  yes=1          # skip confirmation prompt"
	@echo "  layers=...     # advanced: build/remove selected layers directly"
	@echo "  overwrite=1    # deprecated alias for replace=1"
	@echo ""
	@echo "Advanced examples:"
	@echo "  make build target=project"
	@echo "  make build profile=go-dev replace=1"
	@echo "  make build layers=hooks"
	@echo "  make remove layers=hooks,permissions"
	@echo "  make show profile=go-dev"
	@echo "  make show profile=default fragment=git"
	@echo "  make show fragment=aws/safety.json"
	@echo "  make probe profile=infra-dev tool=Bash command='git push --force origin main'"
	@echo "  make probe fragment=git/safety.json tool=Bash command='git push --force origin main'"

build: ## Build settings.json (profile-first; layers are advanced)
	@$(SCRIPT) $(FLAGS)

repo: ## Set up a repo with guardrails + CLAUDE.md
	@$(SCRIPT) --init $(FLAGS)

remove: ## Remove selected layers from settings.json
	@$(SCRIPT) --remove --target $(target) $(if $(layers),--layers $(layers)) $(if $(dry),--dry-run) $(if $(yes),--yes)

list: ## List available fragments
	@$(SCRIPT) --list

profiles: ## List available profiles
	@$(SCRIPT) --list-profiles

show: ## Show a profile's effective fragments or a fragment definition
	@if [ -n "$(profile)" ]; then \
		$(SCRIPT) --show-profile $(profile) $(if $(fragment),--filter $(fragment)) $(if $(fragement),--filter $(fragement)); \
	elif [ -n "$(fragment)" ] || [ -n "$(fragement)" ]; then \
		$(SCRIPT) --show $(or $(fragment),$(fragement)); \
	else \
		echo "Usage: make show [profile=name | fragment=name]" >&2; \
		$(SCRIPT) --list-profiles; \
		exit 1; \
	fi

probe: ## Explain allow/deny for the merged build, a profile, or a fragment
	@bash $(REPO_ROOT)/scripts/probe-fragment.sh \
		$(if $(fragment),--fragment "$(fragment)") \
		$(if $(profile),--profile "$(profile)") \
		--event "$(event)" \
		--tool "$(tool)" \
		$(if $(matcher),--matcher "$(matcher)") \
		$(if $(hook),--hook "$(hook)") \
		$(if $(command),--command "$(command)") \
		$(if $(input),--input '$(input)') \
		$(if $(expect),--expect "$(expect)")

test: ## Run the test suite
	@$(REPO_ROOT)/tests/run-tests.sh
