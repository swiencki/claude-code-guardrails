# Claude Code Guardrails

A modular, composable guardrail system for Claude Code. Drop in the layers you need, run `make build`, and get a working `.claude/settings.json`.

## Prerequisites

- **[Claude Code](https://claude.com/claude-code)** - the AI coding agent these guardrails are for
- **jq** - JSON processor (required for build and lint)
- **shellcheck** - bash linter (required for `make lint`)
- **make** - build system

```bash
# Fedora/RHEL
sudo dnf install jq shellcheck make

# Ubuntu/Debian
sudo apt install jq shellcheck make

# macOS
brew install jq shellcheck make
```

## Quick Start

```bash
# Initialize a project with guardrails + CLAUDE.md
make init target=~/my-project

# List available guardrail fragments
make list

# Build all layers to this repo's .claude/settings.json
make build

# Preview what would be generated (no files written)
make build dry=1

# Install to your user-level settings (applies to all projects)
# Merges with existing settings - preserves model, plugins, etc.
make build target=user

# Install to a specific project
make build target=~/my-project

# Install specific layers only
make build layers=hooks                   # hooks only
make build layers=permissions             # permissions only
make build layers=sub-agents              # sub-agents only
make build layers=hooks,permissions       # hooks + permissions

# Combine layer selection with target
make build layers=hooks target=user       # hooks to user settings
make build layers=hooks dry=1             # preview hooks only

# Remove layers from an existing settings.json
make remove layers=hooks target=user      # remove hooks from user settings
make remove dry=1 layers=hooks            # preview removal

# Run the test suite (90 tests)
make test
```

## Project Structure

```
layers/
├── 1-claude-md/          # Soft guidance (CLAUDE.md templates)
├── 2-hooks/              # Hard guardrails (merged into settings.json)
│   ├── aws/              # AWS CLI safety
│   ├── azure/            # Azure CLI safety
│   ├── ci-cd/            # CI/CD pipeline protection
│   ├── git/              # Git operation safety
│   ├── kubernetes/       # kubectl safety
│   ├── packages/         # Package publish protection
│   ├── security/         # rm, secrets, supply chain
│   └── terraform/        # Terraform safety
├── 3-permissions/        # Tool-level allow/deny presets
│   └── presets/          # Read-only, standard-dev, etc.
├── 4-sub-agents/         # Scoped agents (copied to .claude/agents/)
├── 5-agent-teams/        # Agent team configs (planned)
└── 6-enterprise/         # Org policy templates (planned)
scripts/
└── build-settings.sh     # Merges fragments into .claude/settings.json
tests/                    # 130 tests across 9 files
Makefile                  # Build interface
```

Run `make list` to see all available fragments and their descriptions.

## The Six Layers

Claude Code provides a layered guardrail system. Each layer serves a different purpose and enforcement level.

| Layer | Enforcement | Best For |
|---|---|---|
| [CLAUDE.md](#1-claudemd) | Soft (LLM follows instructions) | Workflow preferences, coding conventions |
| [Hooks](#2-hooks) | Hard (shell scripts) | Blocking dangerous commands, validation gates |
| [Permissions](#3-permissions) | Hard (tool-level) | Controlling which tools/commands need approval |
| [Sub-agents](#4-sub-agents) | Hard (scoped tool access) | Restricting capabilities for delegated tasks |
| [Agent Teams](#5-agent-teams) | Hard (independent sessions) | Parallel work with isolated guardrails |
| [Enterprise/Org Policies](#6-enterpriseorg-policies) | Hard (organization-managed) | Company-wide restrictions across all users |

### 1. CLAUDE.md

Natural language instructions that Claude reads and follows. Not mechanically enforced - it's guidance, not a gate.

**When to use:** Coding conventions, workflow preferences, project-specific rules you trust Claude to follow.

**Limitation:** Context window pressure can cause Claude to miss or override these instructions. Don't rely on CLAUDE.md alone for critical safety rules.

Copy `layers/1-claude-md/CLAUDE.md` to your project root and customize it.

### 2. Hooks

Shell commands that execute at specific lifecycle points via `PreToolUse`. They block execution with a non-zero exit code. Claude cannot bypass them.

**When to use:** Preventing dangerous commands, enforcing validation before commits, catching security issues in real-time.

**Adding a new hook:** Create a JSON file in `layers/2-hooks/` following this format:

```json
{
  "description": "What this hook does",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"$CLAUDE_TOOL_INPUT\" | jq -e '.command | test(\"dangerous-pattern\") | not'",
            "statusMessage": "Checking for dangerous pattern"
          }
        ]
      }
    ]
  }
}
```

Then run `make build` to regenerate `.claude/settings.json`.

### 3. Permissions

Tool-level allow/deny rules. Simple and declarative - no scripting needed.

**When to use:** Allowing read-only commands to auto-run while requiring approval for state-changing operations.

**Adding a preset:** Create a JSON file in `layers/3-permissions/` with `permissions.allow` and `permissions.deny` arrays. The build script deduplicates and merges all presets.

**Limitation:** Deny rules match exact patterns, so variants of a command may slip through. Combine with hooks for reliable blocking.

### 4. Sub-agents

Custom agents with scoped tool restrictions, custom permissions, and their own hooks. Installed to `.claude/agents/` as individual JSON files (not merged into `settings.json`).

**When to use:** Delegating tasks where you want to limit what tools the agent can access.

**Adding an agent:** Create a JSON file in `layers/4-sub-agents/` with `name`, `description`, `prompt`, `tools`, and `permissions` fields. Run `make build` to copy it to the target.

**Constraint:** Sub-agents cannot spawn other sub-agents (no infinite recursion).

### 5. Agent Teams

Multiple independent Claude sessions that coordinate and divide work in parallel. Each session has its own guardrails. *(Planned)*

### 6. Enterprise/Org Policies

Organization-managed policies that override user and project settings. Can restrict the use of `--dangerously-skip-permissions` across all member CLIs. *(Planned)*

**Resolution priority:** Enterprise > User > Project > Plugin.

## Choosing the Right Layer

```
Is it critical that this rule CANNOT be bypassed?
  |-- Yes
  |   |-- Does it need pattern matching / complex logic? -> Hooks
  |   |-- Is it a simple tool allow/deny? -> Permissions
  |   |-- Is it scoped to a delegated task? -> Sub-agents
  |   +-- Does it apply across the whole org? -> Enterprise Policies
  +-- No -> CLAUDE.md
```

## Testing

Run the full test suite:

```bash
make test
```

The test suite (118 tests) covers:

| Category | Tests | What it verifies |
|---|---|---|
| CLI | 14 | `make help`, `make list`, exit codes, layers, dry, targets |
| Layers | 16 | All/single/multiple layer selection |
| Merge | 11 | Preserves existing settings, single layer merge, idempotency |
| Hooks | 9 | Consolidation, matchers (Bash, Write, Edit, Read), valid JSON |
| Hook Behavior | 41 | Runs hook commands against test inputs (block vs allow) |
| Sub-agents | 18 | File copy, dry-run, remove, isolation from settings.json |
| Remove | 9 | `make remove` for hooks, permissions, all; preserves other settings |
| Clean | 2 | `make clean` removes generated file |

Run a specific test file:

```bash
./tests/run-tests.sh hook-behavior
./tests/run-tests.sh merge hooks
```

## Contributing

1. Add a new fragment to the appropriate `layers/` directory
2. Run `make test` to verify it merges correctly
3. Submit a PR

## References

- [Anthropic - Building Safeguards for Claude](https://www.anthropic.com/news/building-safeguards-for-claude)
- [Claude Code Hooks: Guardrails That Actually Work](https://paddo.dev/blog/claude-code-hooks-guardrails/)
- [Claude Code Extensions Explained](https://muneebsa.medium.com/claude-code-extensions-explained-skills-mcp-hooks-subagents-agent-teams-plugins-9294907e84ff)
- [GUARDRAILS.md Protocol](https://guardrails.md/)

## License

MIT
