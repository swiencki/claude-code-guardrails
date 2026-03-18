REPO_ROOT := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
SCRIPT := $(REPO_ROOT)/scripts/build-settings.sh
TARGET ?= project
LAYERS ?=

# Build --layers flag from LAYERS variable
ifneq ($(LAYERS),)
  LAYERS_FLAG := --layers $(LAYERS)
else
  LAYERS_FLAG :=
endif

.PHONY: help build list dry-run test clean

help: ## Show this help
	@echo "Usage: make <target> [TARGET=user|project|/path] [LAYERS=hooks,permissions,...]"
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
	@echo "  hooks             PreToolUse hook guardrails"
	@echo "  permissions       tool allow/deny rules"
	@echo "  sub-agents        scoped agent definitions"
	@echo "  (default: all layers)"
	@echo ""
	@echo "Examples:"
	@echo "  make build                                  # all layers to repo"
	@echo "  make build TARGET=user                      # all layers to user settings"
	@echo "  make build LAYERS=hooks                     # hooks only"
	@echo "  make build LAYERS=hooks,permissions          # hooks + permissions"
	@echo "  make build LAYERS=hooks TARGET=user          # hooks to user settings"
	@echo "  make dry-run LAYERS=hooks                   # preview hooks only"

build: ## Build settings.json from selected layers
	@$(SCRIPT) --target $(TARGET) $(LAYERS_FLAG)

list: ## List available fragments per layer
	@$(SCRIPT) --list

dry-run: ## Preview merged output without writing
	@$(SCRIPT) --target $(TARGET) $(LAYERS_FLAG) --dry-run

test: ## Run the test suite
	@$(REPO_ROOT)/tests/run-tests.sh

clean: ## Remove generated .claude/settings.json
	@rm -f $(REPO_ROOT)/.claude/settings.json
	@echo "Removed $(REPO_ROOT)/.claude/settings.json"
