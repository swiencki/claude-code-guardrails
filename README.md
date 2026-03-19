# Claude Code Guardrails

A modular, composable guardrail system for Claude Code. Drop in the layers you need, run `make build`, and get a working `.claude/settings.json`.

## Prerequisites

- **[Claude Code](https://claude.com/claude-code)** - the AI coding agent these guardrails are for
- **jq** - JSON processor (required for build)
- **shellcheck** - bash linter (required for CI)
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

Run `make help` for all commands and options.

```bash
# Preview a profile
make build profile=go-dev dry=1

# Install (defaults to user settings, applies to all projects)
make build profile=go-dev

# Or set up a specific repo with guardrails + CLAUDE.md
make repo profile=infra-dev target=~/my-project
```


## Project Structure

```
profiles/                 # Curated fragment bundles
├── go-dev.json           # Go development
├── python-dev.json       # Python development
├── infra-dev.json        # Infrastructure/platform work
└── readonly-review.json  # Code review and audit
layers/
├── 1-claude-md/          # Soft guidance (CLAUDE.md templates)
├── 2-hooks/              # Hard guardrails (merged into settings.json)
│   ├── aws/              # AWS CLI safety
│   ├── azure/            # Azure CLI safety
│   ├── ci-cd/            # CI/CD pipeline and make deploy protection
│   ├── gh/               # GitHub CLI (merge, workflow, release)
│   ├── git/              # Git safety and protected branch guards
│   ├── kubernetes/       # kubectl safety and prod context protection
│   ├── packages/         # Package publish protection
│   ├── security/         # rm, secrets, credentials, env, supply chain
│   └── terraform/        # Terraform safety
├── 3-permissions/        # Tool-level allow/deny presets
│   └── presets/          # Read-only, standard-dev, etc.
├── 4-sub-agents/         # Scoped agents (copied to .claude/agents/)
├── 5-agent-teams/        # Agent team configs (planned)
└── 6-enterprise/         # Org policy templates (planned)
scripts/
└── build-settings.sh     # Merges fragments into .claude/settings.json
tests/                    # see tests/README.md
Makefile
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
            "command": "jq -e '.tool_input.command // \"\" | test(\"dangerous-pattern\") | not' >/dev/null",
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

## Profiles

Profiles are curated bundles of fragments for common workflows. Instead of picking individual fragments, choose a profile that matches how you work.

```bash
# See what's available
make profiles

# Preview a profile
make build profile=go-dev dry=1

# Install a profile
make build profile=go-dev
```

| Profile | Hooks | Permissions | Sub-agents | Use case |
|---|---|---|---|---|
| `go-dev` | git, security, packages | standard-dev | reviewer, explorer | Go app/backend development |
| `python-dev` | git, security, packages | standard-dev | reviewer, docs-reviewer | Python development |
| `infra-dev` | git, security, terraform, k8s, azure, aws, ci-cd, gh | standard-dev | explorer, release-reviewer | Infrastructure/platform work |
| `readonly-review` | secret scanning only | read-only | reviewer, docs-reviewer, explorer | Code review, audit, spelunking |

Profiles merge with existing settings by default, or replace them with `overwrite=1`. Switching profiles automatically removes sub-agents that aren't in the new profile.

## Hooks vs Permissions - When to Use Which

The two most commonly used guardrail layers are hooks and permissions. They solve different problems and work best together.

### Hooks

- Shell scripts that run before/after tool calls via lifecycle events (e.g., `PreToolUse`)
- **Never prompt the user** - they silently block (non-zero exit) or silently allow
- Can output an error message explaining why something was blocked
- Full shell power for matching - regex, jq, grep, any logic you need
- Hard to bypass - catches command variants like `--force`, `-f`, `--force-with-lease` with a single regex
- Slight performance overhead since each hook spawns a shell process
- 12 lifecycle events available (pre/post for each tool type)

**Use hooks when:**
- You need pattern matching to catch dangerous flags regardless of position (e.g., `--mode Complete` anywhere in an `az` command)
- You want to block a category of behavior, not just one exact string
- You need context-aware logic (e.g., block `kubectl delete` only in production namespaces)
- You want to validate content before it's committed (lint, secret scanning)
- The rule is safety-critical and must not be bypassable

**Real-world examples:**
- Block `az deployment group create --mode Complete` (deletes all resources not in template)
- Block `git push --force` and all its variants (`-f`, `--force-with-lease`, `--force-if-includes`)
- Prevent committing files containing secrets or API keys
- Block `terraform destroy` without an explicit plan file

### Permissions

- Declarative allow/deny/ask rules matched against tool name + command string
- **Three modes:**
  - `allow` - never prompts, always runs automatically
  - `deny` - never prompts, always blocks silently
  - `ask` - always prompts the user for approval
- Exact string prefix matching only - no regex, no pattern logic
- Instant evaluation (string comparison, no shell overhead)
- Easy to bypass with command variants since matching is literal
- Scoped per tool (Bash, Read, Write, etc.)

**Use permissions when:**
- You want common read-only commands to run without prompting every time (e.g., `git status`, `git diff`, `git log`)
- You want simple "always block" rules for commands you never use (e.g., `rm -rf /`)
- You want to require manual approval for specific tools or commands (ask mode)
- You need zero-overhead, instant evaluation
- The exact command string is predictable and won't have variants

**Real-world examples:**
- Auto-allow `git status`, `git diff`, `git log`, `git branch` (no more approval prompts)
- Auto-deny `rm -rf` as a simple safety net
- Ask before any `git push` or `git commit`
- Allow all Read tool usage but ask before Write

### Using them together

Permissions and hooks are complementary, not competing. A strong setup uses both:

- **Permissions** handle the routine - auto-allow safe commands so Claude isn't constantly asking for approval
- **Hooks** handle the dangerous - pattern-match and block destructive operations that permissions can't reliably catch

```
Permissions (fast, simple):     "allow git status, git diff, git log"
Hooks (thorough, pattern-based): "block any command containing --force or --mode Complete"
```

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

```bash
make test                              # run all tests
./tests/run-tests.sh hook-behavior     # run a specific test file
./tests/run-tests.sh merge hooks       # run multiple test files
```

See [tests/README.md](tests/README.md) for what each test file covers.

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
