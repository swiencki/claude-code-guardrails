# Claude Code Guardrails

A practical guide to the six guardrail layers available in Claude Code, with ready-to-use examples.

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

## 1. CLAUDE.md

Natural language instructions that Claude reads and follows. Not mechanically enforced - it's guidance, not a gate.

**When to use:** Coding conventions, workflow preferences, project-specific rules you trust Claude to follow.

**Limitation:** Context window pressure can cause Claude to miss or override these instructions. Don't rely on CLAUDE.md alone for critical safety rules.

```markdown
## Rules
- Never modify files under `deploy/` without asking first
- Always run `make test` before suggesting a commit
- Use snake_case for all Python function names
```

See [examples/claude-md/](examples/claude-md/) for more examples.

## 2. Hooks

Shell commands that execute at specific lifecycle points. They block execution with a non-zero exit code. Claude cannot bypass them.

**When to use:** Preventing dangerous commands, enforcing validation before commits, catching security issues in real-time.

**12 lifecycle events** including `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, and `Stop`.

```json
{
  "hooks": {
    "Bash": {
      "pre": "echo \"$CLAUDE_TOOL_INPUT\" | jq -e '.command | test(\"push.*(--force|-f)\") | not'"
    }
  }
}
```

See [examples/hooks/](examples/hooks/) for more examples.

## 3. Permissions

Tool-level allow/deny rules in `settings.json`. Simple and declarative - no scripting needed.

**When to use:** Allowing read-only commands to auto-run while requiring approval for state-changing operations.

**Limitation:** Deny rules match exact patterns, so variants of a command may slip through. Combine with hooks for reliable blocking.

```json
{
  "permissions": {
    "allow": ["Read", "Glob", "Grep", "Bash(git status)", "Bash(git diff)", "Bash(git log)"],
    "deny": ["Bash(rm -rf *)", "Bash(curl *)"]
  }
}
```

See [examples/permissions/](examples/permissions/) for more examples.

## 4. Sub-agents

Custom agents with scoped tool restrictions, custom permissions, and their own hooks.

**When to use:** Delegating tasks where you want to limit what tools the agent can access. For example, a "reviewer" sub-agent that can only read files, not edit them.

**Constraint:** Sub-agents cannot spawn other sub-agents (no infinite recursion).

```json
{
  "name": "reviewer",
  "description": "Reviews code for quality issues",
  "tools": ["Read", "Glob", "Grep"],
  "permissions": {
    "deny": ["Edit", "Write", "Bash"]
  }
}
```

See [examples/sub-agents/](examples/sub-agents/) for more examples.

## 5. Agent Teams

Multiple independent Claude sessions that coordinate and divide work in parallel. Each session has its own guardrails.

**When to use:** Large tasks that benefit from parallelism, where each agent needs different tool access.

**Launched:** February 2026 alongside Opus 4.6.

## 6. Enterprise/Org Policies

Organization-managed policies that override user and project settings. Can restrict the use of `--dangerously-skip-permissions` across all member CLIs.

**When to use:** Company-wide security requirements. Enforced automatically for all organization members.

**Resolution priority:** Enterprise > User > Project > Plugin.

## Choosing the Right Layer

```
Is it critical that this rule CANNOT be bypassed?
  ├── Yes
  │   ├── Does it need pattern matching / complex logic? → Hooks
  │   ├── Is it a simple tool allow/deny? → Permissions
  │   ├── Is it scoped to a delegated task? → Sub-agents
  │   └── Does it apply across the whole org? → Enterprise Policies
  └── No → CLAUDE.md
```

## Recommended Layering Strategy

Start simple, add layers as needed:

1. **CLAUDE.md** for conventions and preferences (start here)
2. **Permissions** to auto-allow safe commands and block dangerous ones
3. **Hooks** for complex validation that permissions can't express
4. **Sub-agents** when delegating tasks that need restricted tool access
5. **Agent Teams** for parallel workflows with isolated guardrails
6. **Enterprise Policies** for organization-wide enforcement

## References

- [Anthropic - Building Safeguards for Claude](https://www.anthropic.com/news/building-safeguards-for-claude)
- [Claude Code Hooks: Guardrails That Actually Work](https://paddo.dev/blog/claude-code-hooks-guardrails/)
- [Claude Code Extensions Explained](https://muneebsa.medium.com/claude-code-extensions-explained-skills-mcp-hooks-subagents-agent-teams-plugins-9294907e84ff)
- [GUARDRAILS.md Protocol](https://guardrails.md/)

## License

MIT
