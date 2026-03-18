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
# List available guardrail fragments
make list

# Preview what would be generated (no files written)
make dry-run

# Build all layers to this repo's .claude/settings.json
make build

# Install to your user-level settings (applies to all projects)
# Merges with existing settings - preserves model, plugins, etc.
make build TARGET=user

# Install to a specific project
make build TARGET=~/my-project

# Install specific layers only
make build LAYERS=hooks                   # hooks only
make build LAYERS=permissions             # permissions only
make build LAYERS=hooks,permissions       # hooks + permissions

# Combine layer selection with target
make build LAYERS=hooks TARGET=user       # hooks to user settings
make dry-run LAYERS=hooks                 # preview hooks only

# Run the test suite (46 tests)
make test
```

## Project Structure

```
layers/
├── 1-claude-md/              # Soft guidance (CLAUDE.md templates)
├── 2-hooks/                  # Hard guardrails (JSON fragments, merged by build script)
│   ├── azure-safety.json     # Blocks az --mode Complete
│   ├── git-safety.json       # Blocks force push, hard reset, etc.
│   ├── secret-protection.json # Blocks secret file access/leaks
│   └── ci-cd-protection.json # Blocks CI/CD pipeline modifications
├── 3-permissions/            # Tool-level allow/deny presets
│   ├── read-only.json        # Read-only access
│   └── standard-dev.json     # Standard dev (read + test + lint)
├── 4-sub-agents/             # Scoped agent definitions
│   └── reviewer.json         # Read-only code reviewer
├── 5-agent-teams/            # Agent team configs (planned)
└── 6-enterprise/             # Org policy templates (planned)
scripts/
└── build-settings.sh         # Merges fragments into .claude/settings.json
tests/
└── run-tests.sh              # 37 tests covering build, merge, and idempotency
.claude/
└── settings.json             # Generated output (do not edit directly)
Makefile                      # Build interface
```

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

Custom agents with scoped tool restrictions, custom permissions, and their own hooks.

**When to use:** Delegating tasks where you want to limit what tools the agent can access.

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

The test suite (46 tests) covers:

| Category | What it verifies |
|---|---|
| CLI Options | `make help`, `make list`, exit codes, LAYERS documentation |
| Dry Run | No files written, correct preview output |
| Build All | Both hooks and permissions present |
| Single Layer | `LAYERS=hooks` and `LAYERS=permissions` isolation |
| Multiple Layers | `LAYERS=hooks,permissions` includes both |
| Invalid Layer | Unknown layer name exits with error |
| Hook Consolidation | Multiple fragments merge under one matcher |
| Merge Existing | Preserves model, plugins, and other settings |
| Merge Single Layer | Adding hooks doesn't touch existing permissions |
| Idempotency | Running twice doesn't duplicate hooks |
| Hook Content | Specific guardrails (force push, az Complete, secrets) present |
| Edge Cases | Invalid target, valid JSON output, user path resolution |
| Clean | `make clean` removes generated file |

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
